import os
import signal
import subprocess
import sys
import time
from dataclasses import dataclass


REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
AI_QUEUE_NAME = os.getenv("AI_QUEUE_NAME", "calm_clarity_ai")
WORKER_COUNT = max(1, int(os.getenv("AI_WORKER_COUNT", "2")))
RESTART_DELAY_SECONDS = max(1, int(os.getenv("AI_WORKER_RESTART_DELAY_SECONDS", "3")))
MAX_RESTARTS_PER_WORKER = max(1, int(os.getenv("AI_WORKER_MAX_RESTARTS", "100")))


@dataclass
class WorkerProcess:
    slot: int
    restarts: int
    process: subprocess.Popen


def _worker_command() -> list[str]:
    return [sys.executable, "worker.py"]


def _spawn_worker(slot: int) -> subprocess.Popen:
    env = os.environ.copy()
    env["REDIS_URL"] = REDIS_URL
    env["AI_QUEUE_NAME"] = AI_QUEUE_NAME
    env["AI_WORKER_NAME"] = f"worker-{slot}-{int(time.time())}"
    return subprocess.Popen(_worker_command(), env=env)


def _terminate_process(proc: subprocess.Popen, timeout_seconds: int = 10) -> None:
    if proc.poll() is not None:
        return

    proc.terminate()
    try:
        proc.wait(timeout=timeout_seconds)
        return
    except subprocess.TimeoutExpired:
        pass

    proc.kill()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass


def main() -> None:
    workers: list[WorkerProcess] = []
    shutdown_requested = {"flag": False}

    def _request_shutdown(*_: object) -> None:
        shutdown_requested["flag"] = True

    signal.signal(signal.SIGINT, _request_shutdown)
    signal.signal(signal.SIGTERM, _request_shutdown)

    for slot in range(1, WORKER_COUNT + 1):
        workers.append(WorkerProcess(slot=slot, restarts=0, process=_spawn_worker(slot)))

    while not shutdown_requested["flag"]:
        for index, item in enumerate(list(workers)):
            return_code = item.process.poll()
            if return_code is None:
                continue

            if item.restarts >= MAX_RESTARTS_PER_WORKER:
                print(
                    f"[supervisor] worker slot={item.slot} exceeded max restarts "
                    f"({MAX_RESTARTS_PER_WORKER}); shutting down supervisor."
                )
                shutdown_requested["flag"] = True
                break

            print(
                f"[supervisor] worker slot={item.slot} exited with code {return_code}; "
                f"restarting in {RESTART_DELAY_SECONDS}s"
            )
            time.sleep(RESTART_DELAY_SECONDS)
            workers[index] = WorkerProcess(
                slot=item.slot,
                restarts=item.restarts + 1,
                process=_spawn_worker(item.slot),
            )

        time.sleep(1)

    for item in workers:
        _terminate_process(item.process)


if __name__ == "__main__":
    main()
