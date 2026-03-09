import os
import sys
import socket
import threading
import time

from redis import Redis
from rq import Queue, Worker

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
AI_QUEUE_NAME = os.getenv("AI_QUEUE_NAME", "calm_clarity_ai")
WORKER_HEARTBEAT_INTERVAL_SECONDS = int(os.getenv("AI_WORKER_HEARTBEAT_INTERVAL_SECONDS", "10"))
WORKER_HEARTBEAT_TTL_SECONDS = int(os.getenv("AI_WORKER_HEARTBEAT_TTL_SECONDS", "40"))


def _as_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


WORKER_BURST = _as_bool(os.getenv("AI_WORKER_BURST", "false"))
WORKER_NAME = os.getenv("AI_WORKER_NAME", f"{socket.gethostname()}-{os.getpid()}")


def _heartbeat_key(worker_name: str) -> str:
    return f"ai_worker:{worker_name}:heartbeat"


def _publish_heartbeat(connection: Redis, worker_name: str) -> None:
    now_epoch = int(time.time())
    payload = {
        "worker_name": worker_name,
        "queue": AI_QUEUE_NAME,
        "timestamp": now_epoch,
    }
    connection.setex(
        _heartbeat_key(worker_name),
        max(5, WORKER_HEARTBEAT_TTL_SECONDS),
        str(payload),
    )


def _start_heartbeat_loop(connection: Redis, worker_name: str) -> tuple[threading.Event, threading.Thread]:
    stop_event = threading.Event()

    def _loop() -> None:
        while not stop_event.is_set():
            try:
                _publish_heartbeat(connection, worker_name)
            except Exception:
                pass
            stop_event.wait(max(1, WORKER_HEARTBEAT_INTERVAL_SECONDS))

    thread = threading.Thread(target=_loop, name=f"{worker_name}-heartbeat", daemon=True)
    thread.start()
    return stop_event, thread


def main() -> None:
    try:
        connection = Redis.from_url(REDIS_URL)
        connection.ping()
    except Exception as error:
        print(f"[worker] Redis connection failed: {error}")
        sys.exit(1)

    stop_event, heartbeat_thread = _start_heartbeat_loop(connection, WORKER_NAME)

    queue = Queue(AI_QUEUE_NAME, connection=connection)
    worker = Worker([queue], connection=connection, name=WORKER_NAME)
    try:
        worker.work(burst=WORKER_BURST, with_scheduler=True)
    finally:
        stop_event.set()
        heartbeat_thread.join(timeout=1)
        try:
            connection.delete(_heartbeat_key(WORKER_NAME))
        except Exception:
            pass


if __name__ == "__main__":
    main()