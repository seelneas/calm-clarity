from fastapi import FastAPI, Depends, HTTPException, status, Header, Request
from fastapi.responses import PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
import os
import secrets
import hashlib
import smtplib
import json
import uuid
import time
import threading
from collections import defaultdict
from datetime import datetime, timedelta
from email.message import EmailMessage
from dotenv import load_dotenv
from sqlalchemy.orm import Session
from sqlalchemy import func, text, inspect
from database import engine, Base, get_db, SessionLocal
import models, schemas, auth
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
import requests
from redis import Redis
from rq import Queue, Retry
from rq.registry import StartedJobRegistry, FailedJobRegistry
from rq.job import Job

load_dotenv()

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
CORS_ALLOW_ORIGINS = os.getenv("CORS_ALLOW_ORIGINS", "*")
LOCAL_DEV_ORIGIN_REGEX = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
APP_ENV = os.getenv("APP_ENV", "development")
FRONTEND_BASE_URL = os.getenv("FRONTEND_BASE_URL", "http://localhost:3000")
FRONTEND_ROUTE_MODE = os.getenv("FRONTEND_ROUTE_MODE", "query").lower()
RESET_TOKEN_EXPIRE_MINUTES = int(os.getenv("RESET_TOKEN_EXPIRE_MINUTES", "30"))
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
AI_PROVIDER = os.getenv("AI_PROVIDER", "auto").strip().lower()
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.1-8b-instant")
GROQ_BASE_URL = os.getenv("GROQ_BASE_URL", "https://api.groq.com/openai/v1")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-1.5-flash")
GEMINI_BASE_URL = os.getenv("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta")
AI_PROMPT_VERSION = os.getenv("AI_PROMPT_VERSION", "v2")
AI_MAX_TRANSCRIPT_CHARS = int(os.getenv("AI_MAX_TRANSCRIPT_CHARS", "4000"))
AI_DAILY_QUOTA = int(os.getenv("AI_DAILY_QUOTA", "40"))
AI_JOB_MAX_ATTEMPTS = int(os.getenv("AI_JOB_MAX_ATTEMPTS", "3"))
AI_JOB_POLL_INTERVAL_MS = int(os.getenv("AI_JOB_POLL_INTERVAL_MS", "700"))
AI_STALE_PROCESSING_SECONDS = int(os.getenv("AI_STALE_PROCESSING_SECONDS", "600"))
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
AI_QUEUE_NAME = os.getenv("AI_QUEUE_NAME", "calm_clarity_ai")
AI_JOB_TIMEOUT_SECONDS = int(os.getenv("AI_JOB_TIMEOUT_SECONDS", "180"))
AI_OPS_QUEUE_WARN_DEPTH = int(os.getenv("AI_OPS_QUEUE_WARN_DEPTH", "100"))
AI_OPS_FAILED_REGISTRY_WARN = int(os.getenv("AI_OPS_FAILED_REGISTRY_WARN", "20"))
AI_OPS_MIN_HEARTBEAT_WORKERS = int(os.getenv("AI_OPS_MIN_HEARTBEAT_WORKERS", "1"))
AI_WORKER_HEARTBEAT_STALE_SECONDS = int(os.getenv("AI_WORKER_HEARTBEAT_STALE_SECONDS", "40"))
GOOGLE_CALENDAR_SYNC_DEFAULT_INTERVAL_MINUTES = int(
    os.getenv("GOOGLE_CALENDAR_SYNC_DEFAULT_INTERVAL_MINUTES", "5")
)
SEMANTIC_MEMORY_ENABLED = os.getenv("SEMANTIC_MEMORY_ENABLED", "true").strip().lower() in {"1", "true", "yes"}
SEMANTIC_MEMORY_MODEL = os.getenv("SEMANTIC_MEMORY_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
SEMANTIC_MEMORY_TOP_K = int(os.getenv("SEMANTIC_MEMORY_TOP_K", "5"))
OBS_METRICS_WINDOW_SECONDS = int(os.getenv("OBS_METRICS_WINDOW_SECONDS", "900"))
OBS_ERROR_RATE_WARN = float(os.getenv("OBS_ERROR_RATE_WARN", "0.05"))
OBS_ERROR_RATE_FAIL = float(os.getenv("OBS_ERROR_RATE_FAIL", "0.15"))
OBS_LATENCY_P95_WARN_MS = float(os.getenv("OBS_LATENCY_P95_WARN_MS", "1200"))
OBS_LATENCY_P95_FAIL_MS = float(os.getenv("OBS_LATENCY_P95_FAIL_MS", "3000"))
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY", "")
ADMIN_ALLOWED_EMAILS = {
    email.strip().lower()
    for email in os.getenv("ADMIN_ALLOWED_EMAILS", "").split(",")
    if email.strip()
}
FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")
FCM_SEND_URL = os.getenv("FCM_SEND_URL", "https://fcm.googleapis.com/fcm/send")
FCM_TIMEOUT_SECONDS = int(os.getenv("FCM_TIMEOUT_SECONDS", "10"))
NOTIFICATION_DEVICE_STALE_DAYS = int(os.getenv("NOTIFICATION_DEVICE_STALE_DAYS", "30"))
NOTIFICATION_LOG_WINDOW_HOURS = int(os.getenv("NOTIFICATION_LOG_WINDOW_HOURS", "24"))
NOTIFICATION_FAILURE_WARN_RATE = float(os.getenv("NOTIFICATION_FAILURE_WARN_RATE", "0.20"))
NOTIFICATION_INVALID_TOKEN_MARKERS = [
    marker.strip().lower()
    for marker in os.getenv(
        "NOTIFICATION_INVALID_TOKEN_MARKERS",
        "notregistered,registration-token-not-registered,invalidregistration",
    ).split(",")
    if marker.strip()
]

SMTP_HOST = os.getenv("SMTP_HOST")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("SMTP_USERNAME")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USERNAME or "")
SMTP_USE_TLS = os.getenv("SMTP_USE_TLS", "true").lower() in {"1", "true", "yes"}

_obs_lock = threading.Lock()
_obs_request_total = 0
_obs_error_total = 0
_obs_status_counts = defaultdict(int)
_obs_path_counts = defaultdict(int)
_obs_samples: list[tuple[float, float, int]] = []
_semantic_model_lock = threading.Lock()
_semantic_model = None


def _mood_label(mood: str) -> str:
    mapping = {
        "veryBad": "very low",
        "bad": "low",
        "neutral": "steady",
        "good": "positive",
        "veryGood": "very positive",
    }
    return mapping.get((mood or "").strip(), "mixed")


def _utc_now() -> datetime:
    return datetime.utcnow()


def _obs_prune(now_epoch: float) -> None:
    cutoff = now_epoch - max(60, OBS_METRICS_WINDOW_SECONDS)
    while _obs_samples and _obs_samples[0][0] < cutoff:
        _obs_samples.pop(0)


def _obs_record(path: str, status_code: int, latency_ms: float) -> None:
    global _obs_request_total, _obs_error_total

    now_epoch = time.time()
    with _obs_lock:
        _obs_request_total += 1
        _obs_status_counts[str(status_code)] += 1
        _obs_path_counts[path] += 1
        is_error = 1 if status_code >= 500 else 0
        if is_error:
            _obs_error_total += 1
        _obs_samples.append((now_epoch, max(0.0, latency_ms), is_error))
        _obs_prune(now_epoch)


def _ensure_user_active_column() -> None:
    inspector = inspect(engine)
    try:
        columns = [column["name"] for column in inspector.get_columns("users")]
    except Exception:
        return

    if "is_active" in columns:
        return

    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE users ADD COLUMN is_active INTEGER DEFAULT 1"))
        connection.execute(text("UPDATE users SET is_active = 1 WHERE is_active IS NULL"))


def _percentile(values: list[float], quantile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = int(round((len(ordered) - 1) * max(0.0, min(1.0, quantile))))
    return float(ordered[idx])


def _obs_snapshot() -> dict:
    with _obs_lock:
        now_epoch = time.time()
        _obs_prune(now_epoch)
        samples = list(_obs_samples)
        status_counts = dict(_obs_status_counts)
        path_counts = dict(_obs_path_counts)
        total_requests = int(_obs_request_total)
        total_errors = int(_obs_error_total)

    request_count = len(samples)
    error_count = sum(sample[2] for sample in samples)
    latencies = [sample[1] for sample in samples]
    error_rate = (error_count / request_count) if request_count > 0 else 0.0
    rps = request_count / max(1, OBS_METRICS_WINDOW_SECONDS)

    top_paths = sorted(path_counts.items(), key=lambda item: item[1], reverse=True)[:8]

    return {
        "total_requests": total_requests,
        "total_errors": total_errors,
        "window_request_count": request_count,
        "window_error_count": error_count,
        "window_error_rate": float(error_rate),
        "window_rps": float(rps),
        "latency_p50_ms": _percentile(latencies, 0.50),
        "latency_p95_ms": _percentile(latencies, 0.95),
        "latency_avg_ms": float(sum(latencies) / len(latencies)) if latencies else 0.0,
        "status_counts": status_counts,
        "top_paths": [{"path": path, "count": int(count)} for path, count in top_paths],
    }


def _redis_connection() -> Redis:
    return Redis.from_url(REDIS_URL)


def _ai_queue() -> Queue:
    return Queue(AI_QUEUE_NAME, connection=_redis_connection(), default_timeout=AI_JOB_TIMEOUT_SECONDS)


def _retry_intervals(max_attempts: int) -> list[int]:
    if max_attempts <= 1:
        return []
    base = [5, 15, 45, 120, 300, 600]
    needed = max_attempts - 1
    if needed <= len(base):
        return base[:needed]
    return base + [600] * (needed - len(base))


def _enqueue_ai_job(job_id: str, max_attempts: int) -> str:
    queue = _ai_queue()
    retry = Retry(max=max_attempts, interval=_retry_intervals(max_attempts))
    queued_job = queue.enqueue(
        "ai_tasks.run_ai_job",
        job_id,
        job_timeout=AI_JOB_TIMEOUT_SECONDS,
        retry=retry,
    )
    return queued_job.id


def _get_or_create_notification_preferences(db: Session, user_id: int) -> models.NotificationPreference:
    prefs = db.query(models.NotificationPreference).filter(
        models.NotificationPreference.user_id == user_id,
    ).first()
    if prefs is not None:
        return prefs

    now = _utc_now()
    prefs = models.NotificationPreference(
        user_id=user_id,
        notifications_enabled=1,
        push_enabled=1,
        daily_reminder_enabled=0,
        daily_reminder_hour=20,
        daily_reminder_minute=0,
        timezone="UTC",
        updated_at=now,
    )
    db.add(prefs)
    db.flush()
    return prefs


def _prefs_to_schema(prefs: models.NotificationPreference) -> schemas.NotificationPreferencesResponse:
    return schemas.NotificationPreferencesResponse(
        notifications_enabled=bool(prefs.notifications_enabled),
        push_enabled=bool(prefs.push_enabled),
        daily_reminder_enabled=bool(prefs.daily_reminder_enabled),
        daily_reminder_hour=int(prefs.daily_reminder_hour),
        daily_reminder_minute=int(prefs.daily_reminder_minute),
        timezone=prefs.timezone or "UTC",
    )


def _send_fcm_push(token: str, title: str, body: str, data: dict | None = None) -> tuple[bool, str | None]:
    if not FCM_SERVER_KEY.strip():
        return False, "FCM_SERVER_KEY is not configured"

    payload = {
        "to": token,
        "notification": {
            "title": title,
            "body": body,
            "sound": "default",
        },
        "data": data or {},
        "priority": "high",
    }

    try:
        response = requests.post(
            FCM_SEND_URL,
            headers={
                "Authorization": f"key={FCM_SERVER_KEY}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=FCM_TIMEOUT_SECONDS,
        )
    except Exception as error:
        return False, str(error)

    if response.status_code >= 400:
        return False, f"fcm_http_{response.status_code}: {response.text[:300]}"

    body_json = response.json() if response.content else {}
    failure_count = int(body_json.get("failure", 0))
    if failure_count > 0:
        results = body_json.get("results", [])
        first_error = "FCM send failed"
        if results and isinstance(results[0], dict):
            first_error = str(results[0].get("error") or first_error)
        return False, first_error

    return True, None


def _is_invalid_push_token_error(error_message: str | None) -> bool:
    message = (error_message or "").strip().lower()
    if not message:
        return False
    return any(marker in message for marker in NOTIFICATION_INVALID_TOKEN_MARKERS)


def _stale_device_cutoff() -> datetime:
    return _utc_now() - timedelta(days=max(1, NOTIFICATION_DEVICE_STALE_DAYS))


def _recent_notification_cutoff() -> datetime:
    return _utc_now() - timedelta(hours=max(1, NOTIFICATION_LOG_WINDOW_HOURS))


def _dispatch_push_notification(
    db: Session,
    *,
    user_id: int,
    event_type: str,
    title: str,
    body: str,
    data: dict | None = None,
) -> schemas.NotificationTriggerResponse:
    prefs = _get_or_create_notification_preferences(db, user_id)
    devices = db.query(models.NotificationDevice).filter(
        models.NotificationDevice.user_id == user_id,
        models.NotificationDevice.push_enabled == 1,
        models.NotificationDevice.last_seen_at >= _stale_device_cutoff(),
    ).all()

    attempted = len(devices)
    sent = 0
    failed = 0
    now = _utc_now()

    if not prefs.notifications_enabled or not prefs.push_enabled:
        attempted = 0

    if attempted == 0:
        log = models.NotificationLog(
            id=str(uuid.uuid4()),
            user_id=user_id,
            event_type=event_type,
            channel="push",
            title=title,
            body=body,
            status="skipped",
            provider="fcm",
            error_message=None,
            created_at=now,
        )
        db.add(log)
        return schemas.NotificationTriggerResponse(
            event_type=event_type,
            attempted=0,
            sent=0,
            failed=0,
        )

    for device in devices:
        ok, error_message = _send_fcm_push(device.push_token, title, body, data)
        log = models.NotificationLog(
            id=str(uuid.uuid4()),
            user_id=user_id,
            event_type=event_type,
            channel="push",
            title=title,
            body=body,
            status="sent" if ok else "failed",
            provider="fcm",
            error_message=error_message,
            created_at=now,
        )
        db.add(log)
        if ok:
            device.last_seen_at = now
            device.updated_at = now
            sent += 1
        else:
            if _is_invalid_push_token_error(error_message):
                device.push_enabled = 0
                device.updated_at = now
            failed += 1

    return schemas.NotificationTriggerResponse(
        event_type=event_type,
        attempted=attempted,
        sent=sent,
        failed=failed,
    )


def _notification_delivery_counts(db: Session, *, since: datetime, user_id: int | None = None) -> tuple[int, int]:
    query = db.query(models.NotificationLog).filter(
        models.NotificationLog.channel == "push",
        models.NotificationLog.created_at >= since,
    )
    if user_id is not None:
        query = query.filter(models.NotificationLog.user_id == user_id)

    rows = query.all()
    sent = len([row for row in rows if (row.status or "").strip().lower() == "sent"])
    failed = len([row for row in rows if (row.status or "").strip().lower() == "failed"])
    return sent, failed


def _crisis_resources() -> list[str]:
    return [
        "If you may be in immediate danger, call your local emergency number now.",
        "US/Canada: Call or text 988 (Suicide & Crisis Lifeline).",
        "If outside the US, contact your country’s local crisis hotline.",
    ]


def _contains_self_harm_risk(text: str) -> bool:
    lowered = (text or "").lower()
    keywords = [
        "kill myself",
        "want to die",
        "suicide",
        "end my life",
        "self harm",
        "hurt myself",
        "no reason to live",
    ]
    return any(keyword in lowered for keyword in keywords)


def _entry_moderation_text(payload: schemas.AIAnalyzeEntryRequest) -> str:
    return "\n".join([
        payload.summary or "",
        payload.transcript or "",
        " ".join(payload.tags or []),
    ]).strip()


def _weekly_moderation_text(payload: schemas.AIWeeklyInsightsRequest) -> str:
    parts = [payload.timeframe_label or ""]
    for entry in payload.entries:
        parts.extend([
            entry.summary or "",
            entry.ai_summary or "",
            " ".join(entry.tags or []),
        ])
    return "\n".join(parts).strip()


def _enforce_daily_quota(db: Session, user_id: int) -> None:
    today = datetime.utcnow().strftime("%Y-%m-%d")
    usage = db.query(models.AIUsageDaily).filter(
        models.AIUsageDaily.user_id == user_id,
        models.AIUsageDaily.usage_date == today,
    ).first()
    if usage is None:
        usage = models.AIUsageDaily(user_id=user_id, usage_date=today, request_count=0)
        db.add(usage)
        db.flush()

    if usage.request_count >= AI_DAILY_QUOTA:
        raise HTTPException(
            status_code=429,
            detail="Daily AI quota reached. Please try again tomorrow.",
        )

    usage.request_count += 1


def _log_ai_request(
    db: Session,
    *,
    user_id: int,
    request_type: str,
    status: str,
    input_chars: int,
    output_chars: int = 0,
    provider: str | None = None,
    model: str | None = None,
    job_id: str | None = None,
    error_message: str | None = None,
) -> None:
    now = _utc_now()
    log = models.AIRequestLog(
        id=str(uuid.uuid4()),
        user_id=user_id,
        job_id=job_id,
        request_type=request_type,
        status=status,
        provider=provider,
        model=model,
        prompt_version=AI_PROMPT_VERSION,
        input_chars=max(0, input_chars),
        output_chars=max(0, output_chars),
        error_message=error_message,
        created_at=now,
        completed_at=now,
    )
    db.add(log)


def _tokenize_text(text: str) -> set[str]:
    raw = (text or "").lower()
    for c in ",.!?:;()[]{}\"'\\n\\t\\r":
        raw = raw.replace(c, " ")
    tokens = {part for part in raw.split(" ") if len(part) > 2}
    stopwords = {
        "the", "and", "for", "with", "that", "this", "from", "your", "have", "been", "are", "was", "but", "not", "you",
    }
    return {token for token in tokens if token not in stopwords}


def _entry_memory_text(entry: schemas.AIWeeklyEntryInput) -> str:
    return " ".join([
        entry.summary or "",
        entry.ai_summary or "",
        entry.transcript or "",
        " ".join(entry.tags or []),
    ]).strip()


def _semantic_embedding_model():
    global _semantic_model
    if not SEMANTIC_MEMORY_ENABLED:
        return None

    if _semantic_model is not None:
        return _semantic_model

    with _semantic_model_lock:
        if _semantic_model is not None:
            return _semantic_model
        try:
            from sentence_transformers import SentenceTransformer

            _semantic_model = SentenceTransformer(SEMANTIC_MEMORY_MODEL)
            return _semantic_model
        except Exception:
            _semantic_model = None
            return None


def _embed_texts(texts: list[str]) -> list[list[float]]:
    model = _semantic_embedding_model()
    if model is None or not texts:
        return []

    encoded = model.encode(texts, normalize_embeddings=True)
    return [list(map(float, row)) for row in encoded]


def _cosine_with_normalized(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    return float(sum(x * y for x, y in zip(a, b)))


def _retrieve_memory_snippets(
    query_entries: list[schemas.AIWeeklyEntryInput],
    memory_candidates: list[schemas.AIWeeklyEntryInput] | None = None,
    limit: int = 5,
) -> list[str]:
    if not query_entries:
        return []

    candidates = memory_candidates or query_entries
    if not candidates:
        return []

    top_k = max(1, min(limit, max(1, SEMANTIC_MEMORY_TOP_K)))

    combined_query = " ".join([_entry_memory_text(entry) for entry in query_entries]).strip()
    query_terms = _tokenize_text(combined_query)
    candidate_texts = [_entry_memory_text(entry) for entry in candidates]
    cleaned_candidates = [text for text in candidate_texts if text.strip()]

    query_embeddings = _embed_texts([combined_query]) if combined_query else []
    candidate_embeddings = _embed_texts(cleaned_candidates) if cleaned_candidates else []

    if query_embeddings and candidate_embeddings and len(candidate_embeddings) == len(cleaned_candidates):
        scored_vectors: list[tuple[float, str]] = []
        query_vector = query_embeddings[0]
        for candidate_text, candidate_vector in zip(cleaned_candidates, candidate_embeddings):
            score = _cosine_with_normalized(query_vector, candidate_vector)
            if score > 0:
                scored_vectors.append((score, candidate_text))

        scored_vectors.sort(key=lambda item: item[0], reverse=True)
        snippets: list[str] = []
        for _, text in scored_vectors:
            clipped = text[:220].strip()
            if clipped and clipped not in snippets:
                snippets.append(clipped)
            if len(snippets) >= top_k:
                break
        if snippets:
            return snippets

    scored: list[tuple[float, str]] = []

    for entry in candidates:
        candidate = _entry_memory_text(entry)
        terms = _tokenize_text(candidate)
        overlap = len(query_terms.intersection(terms))
        score = float(overlap)
        if score > 0:
            scored.append((score, candidate))

    scored.sort(key=lambda item: item[0], reverse=True)
    snippets = []
    for _, text in scored[:top_k]:
        clipped = text[:220].strip()
        if clipped and clipped not in snippets:
            snippets.append(clipped)
    return snippets


def _rule_based_ai_reflection(payload: schemas.AIAnalyzeEntryRequest) -> schemas.AIAnalyzeEntryResponse:
    transcript = (payload.transcript or "").strip()
    summary = (payload.summary or "").strip()
    tags = payload.tags or []
    confidence_value = payload.mood_confidence if payload.mood_confidence is not None else 0.0
    confidence_pct = int(max(0, min(100, round(confidence_value * 100))))
    mood_text = _mood_label(payload.mood)

    clipped = transcript[:180].strip()
    if not clipped:
                clipped = summary or "You captured a short reflection today."

    ai_summary = (
        f"You noted a {mood_text} emotional tone with {confidence_pct}% confidence. "
        f"Main theme: {summary if summary else 'daily reflection and self-awareness'}"
    )

    first_tag = tags[0].replace('#', '') if tags else "wellbeing"
    ai_action_items = [
        "Take a 5-minute pause for breathing before your next task.",
        f"Pick one small {first_tag} action and complete it within 24 hours.",
        "Write one sentence tonight about what improved your mood.",
    ]

    ai_mood_explanation = (
        f"The reflection suggests a {mood_text} state based on wording, tone indicators, "
        f"and confidence from your entry signals. Key phrase observed: \"{clipped}\""
    )

    ai_followup_prompt = "What is one specific situation tomorrow where you want to feel calmer, and what will you try first?"

    return schemas.AIAnalyzeEntryResponse(
        ai_summary=ai_summary,
        ai_action_items=ai_action_items,
        ai_mood_explanation=ai_mood_explanation,
        ai_followup_prompt=ai_followup_prompt,
        safety_flag=False,
        crisis_resources=[],
    )


def _ai_system_prompt() -> str:
    return (
        "You are a supportive journaling reflection coach. "
        "Return only valid JSON with keys: ai_summary, ai_action_items, ai_mood_explanation, ai_followup_prompt. "
        "ai_action_items must be an array of 2-4 concise action strings."
    )


def _extract_json_block(text: str) -> str:
    stripped = (text or "").strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        if len(lines) >= 2:
            stripped = "\n".join(lines[1:-1]).strip()

    start = stripped.find("{")
    end = stripped.rfind("}")
    if start != -1 and end != -1 and end > start:
        return stripped[start : end + 1]
    return stripped


def _normalize_ai_response(parsed: dict) -> schemas.AIAnalyzeEntryResponse:
    action_items = parsed.get("ai_action_items", [])
    if isinstance(action_items, str):
        action_items = [action_items]

    return schemas.AIAnalyzeEntryResponse(
        ai_summary=(parsed.get("ai_summary") or "").strip(),
        ai_action_items=[str(item).strip() for item in list(action_items) if str(item).strip()],
        ai_mood_explanation=(parsed.get("ai_mood_explanation") or "").strip(),
        ai_followup_prompt=(parsed.get("ai_followup_prompt") or "").strip(),
        safety_flag=bool(parsed.get("safety_flag", False)),
        crisis_resources=[
            str(item).strip() for item in list(parsed.get("crisis_resources", [])) if str(item).strip()
        ],
    )


def _weekly_system_prompt() -> str:
    return (
        "You are a supportive weekly reflection coach. "
        "Return only valid JSON with keys: weekly_summary, key_patterns, coaching_priorities, next_week_prompt. "
        "key_patterns and coaching_priorities must each contain 2-4 concise strings."
    )


def _normalize_weekly_response(parsed: dict) -> schemas.AIWeeklyInsightsResponse:
    key_patterns = parsed.get("key_patterns", [])
    priorities = parsed.get("coaching_priorities", [])

    if isinstance(key_patterns, str):
        key_patterns = [key_patterns]
    if isinstance(priorities, str):
        priorities = [priorities]

    return schemas.AIWeeklyInsightsResponse(
        weekly_summary=(parsed.get("weekly_summary") or "").strip(),
        key_patterns=[str(item).strip() for item in list(key_patterns) if str(item).strip()],
        coaching_priorities=[str(item).strip() for item in list(priorities) if str(item).strip()],
        next_week_prompt=(parsed.get("next_week_prompt") or "").strip(),
        memory_snippets_used=[
            str(item).strip() for item in list(parsed.get("memory_snippets_used", [])) if str(item).strip()
        ],
        safety_flag=bool(parsed.get("safety_flag", False)),
        crisis_resources=[
            str(item).strip() for item in list(parsed.get("crisis_resources", [])) if str(item).strip()
        ],
    )


def _rule_based_weekly_insights(payload: schemas.AIWeeklyInsightsRequest) -> schemas.AIWeeklyInsightsResponse:
    entries = payload.entries or []
    memory_candidates = payload.memory_candidates or []
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(entries, memory_candidates)
    if not entries:
        return schemas.AIWeeklyInsightsResponse(
            weekly_summary="No entries yet in this period. Start with one short reflection to unlock weekly coaching.",
            key_patterns=[
                "No mood pattern detected yet.",
                "No recurring topics detected yet.",
            ],
            coaching_priorities=[
                "Record at least 3 short entries this week.",
                "Add one concrete next step in each entry.",
            ],
            next_week_prompt="What time of day is easiest for a 2-minute reflection, and how will you protect it this week?",
            memory_snippets_used=[],
        )

    mood_counts = {}
    tag_counts = {}
    for entry in entries:
        mood_counts[entry.mood] = mood_counts.get(entry.mood, 0) + 1
        for tag in entry.tags:
            clean_tag = (tag or "").strip().lower()
            if clean_tag:
                tag_counts[clean_tag] = tag_counts.get(clean_tag, 0) + 1

    dominant_mood = max(mood_counts, key=mood_counts.get)
    sorted_tags = sorted(tag_counts.items(), key=lambda item: item[1], reverse=True)
    top_tag_text = sorted_tags[0][0].replace("#", "") if sorted_tags else "general wellbeing"
    timeframe = payload.timeframe_label or "this period"

    weekly_summary = (
        f"Across {len(entries)} entries in {timeframe}, your dominant emotional tone was "
        f"{_mood_label(dominant_mood)} with recurring focus on {top_tag_text}."
    )
    key_patterns = [
        f"Most frequent mood: {_mood_label(dominant_mood)}.",
        f"Most common topic: {top_tag_text}.",
        "Consistency improves when entries include one clear next action.",
    ]
    coaching_priorities = [
        "Choose one small action each morning and review it at night.",
        "Use short check-ins when stress signals rise.",
        "Keep entries specific: situation, feeling, and next step.",
    ]
    next_week_prompt = "Which single habit would make next week feel 10% calmer, and when will you do it daily?"

    return schemas.AIWeeklyInsightsResponse(
        weekly_summary=weekly_summary,
        key_patterns=key_patterns,
        coaching_priorities=coaching_priorities,
        next_week_prompt=next_week_prompt,
        memory_snippets_used=memory_snippets,
    )


def _openai_weekly_insights(payload: schemas.AIWeeklyInsightsRequest) -> schemas.AIWeeklyInsightsResponse:
    api_base = OPENAI_BASE_URL.rstrip("/")
    endpoint = f"{api_base}/chat/completions"
    memory_candidates = payload.memory_candidates or []
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(payload.entries, memory_candidates)

    prompt_payload = {
        "timeframe_label": payload.timeframe_label,
        "entries": [entry.model_dump() for entry in payload.entries],
        "memory_snippets": memory_snippets,
    }

    response = requests.post(
        endpoint,
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": OPENAI_MODEL,
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": _weekly_system_prompt()},
                {"role": "user", "content": json.dumps(prompt_payload)},
            ],
            "response_format": {"type": "json_object"},
        },
        timeout=15,
    )

    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="AI provider error")

    body = response.json()
    message_text = (
        body.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
    )
    parsed = json.loads(_extract_json_block(message_text))
    return _normalize_weekly_response(parsed)


def _groq_weekly_insights(payload: schemas.AIWeeklyInsightsRequest) -> schemas.AIWeeklyInsightsResponse:
    api_base = GROQ_BASE_URL.rstrip("/")
    endpoint = f"{api_base}/chat/completions"
    memory_candidates = payload.memory_candidates or []
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(payload.entries, memory_candidates)

    prompt_payload = {
        "timeframe_label": payload.timeframe_label,
        "entries": [entry.model_dump() for entry in payload.entries],
        "memory_snippets": memory_snippets,
    }

    response = requests.post(
        endpoint,
        headers={
            "Authorization": f"Bearer {GROQ_API_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": GROQ_MODEL,
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": _weekly_system_prompt()},
                {"role": "user", "content": json.dumps(prompt_payload)},
            ],
            "response_format": {"type": "json_object"},
        },
        timeout=15,
    )

    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="Groq provider error")

    body = response.json()
    message_text = (
        body.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
    )
    parsed = json.loads(_extract_json_block(message_text))
    return _normalize_weekly_response(parsed)


def _gemini_weekly_insights(payload: schemas.AIWeeklyInsightsRequest) -> schemas.AIWeeklyInsightsResponse:
    base = GEMINI_BASE_URL.rstrip("/")
    endpoint = f"{base}/models/{GEMINI_MODEL}:generateContent"
    memory_candidates = payload.memory_candidates or []
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(payload.entries, memory_candidates)

    prompt_payload = {
        "timeframe_label": payload.timeframe_label,
        "entries": [entry.model_dump() for entry in payload.entries],
        "memory_snippets": memory_snippets,
    }

    response = requests.post(
        endpoint,
        params={"key": GEMINI_API_KEY},
        headers={"Content-Type": "application/json"},
        json={
            "systemInstruction": {
                "parts": [{"text": _weekly_system_prompt()}],
            },
            "contents": [
                {
                    "parts": [
                        {"text": json.dumps(prompt_payload)}
                    ]
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "responseMimeType": "application/json",
            },
        },
        timeout=15,
    )

    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="Gemini provider error")

    body = response.json()
    candidates = body.get("candidates", [])
    parts = []
    if candidates:
        parts = candidates[0].get("content", {}).get("parts", [])
    text = ""
    if parts:
        text = parts[0].get("text", "")

    parsed = json.loads(_extract_json_block(text))
    return _normalize_weekly_response(parsed)


def _openai_ai_reflection(payload: schemas.AIAnalyzeEntryRequest) -> schemas.AIAnalyzeEntryResponse:
    api_base = OPENAI_BASE_URL.rstrip("/")
    endpoint = f"{api_base}/chat/completions"
    prompt_payload = {
        "transcript": payload.transcript,
        "summary": payload.summary,
        "mood": payload.mood,
        "mood_confidence": payload.mood_confidence,
        "tags": payload.tags,
    }

    response = requests.post(
        endpoint,
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": OPENAI_MODEL,
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": _ai_system_prompt()},
                {
                    "role": "user",
                    "content": json.dumps(prompt_payload),
                },
            ],
            "response_format": {"type": "json_object"},
        },
        timeout=15,
    )

    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="AI provider error")

    body = response.json()
    message_text = (
        body.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
    )
    parsed = json.loads(_extract_json_block(message_text))

    return _normalize_ai_response(parsed)


def _groq_ai_reflection(payload: schemas.AIAnalyzeEntryRequest) -> schemas.AIAnalyzeEntryResponse:
    api_base = GROQ_BASE_URL.rstrip("/")
    endpoint = f"{api_base}/chat/completions"
    prompt_payload = {
        "transcript": payload.transcript,
        "summary": payload.summary,
        "mood": payload.mood,
        "mood_confidence": payload.mood_confidence,
        "tags": payload.tags,
    }

    response = requests.post(
        endpoint,
        headers={
            "Authorization": f"Bearer {GROQ_API_KEY}",
            "Content-Type": "application/json",
        },
        json={
            "model": GROQ_MODEL,
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": _ai_system_prompt()},
                {"role": "user", "content": json.dumps(prompt_payload)},
            ],
            "response_format": {"type": "json_object"},
        },
        timeout=15,
    )

    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="Groq provider error")

    body = response.json()
    message_text = (
        body.get("choices", [{}])[0]
        .get("message", {})
        .get("content", "")
    )
    parsed = json.loads(_extract_json_block(message_text))
    return _normalize_ai_response(parsed)


def _gemini_ai_reflection(payload: schemas.AIAnalyzeEntryRequest) -> schemas.AIAnalyzeEntryResponse:
    base = GEMINI_BASE_URL.rstrip("/")
    endpoint = f"{base}/models/{GEMINI_MODEL}:generateContent"
    prompt_payload = {
        "transcript": payload.transcript,
        "summary": payload.summary,
        "mood": payload.mood,
        "mood_confidence": payload.mood_confidence,
        "tags": payload.tags,
    }

    response = requests.post(
        endpoint,
        params={"key": GEMINI_API_KEY},
        headers={"Content-Type": "application/json"},
        json={
            "systemInstruction": {
                "parts": [{"text": _ai_system_prompt()}],
            },
            "contents": [
                {
                    "parts": [
                        {"text": json.dumps(prompt_payload)}
                    ]
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "responseMimeType": "application/json",
            },
        },
        timeout=15,
    )

    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="Gemini provider error")

    body = response.json()
    candidates = body.get("candidates", [])
    parts = []
    if candidates:
        parts = candidates[0].get("content", {}).get("parts", [])
    text = ""
    if parts:
        text = parts[0].get("text", "")

    parsed = json.loads(_extract_json_block(text))
    return _normalize_ai_response(parsed)


def _extract_bearer_token(authorization: str = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    return authorization.split(" ", 1)[1]


def _get_current_user(
    token: str = Depends(_extract_bearer_token),
    db: Session = Depends(get_db),
) -> models.User:
    try:
        payload = auth.jwt.decode(token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM])
    except Exception:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    email = payload.get("sub")
    if not email:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user


def _require_admin(
    user: models.User = Depends(_get_current_user),
    admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
) -> models.User:
    if ADMIN_API_KEY.strip() and (admin_key or "").strip() != ADMIN_API_KEY.strip():
        raise HTTPException(status_code=403, detail="Invalid admin key")

    if ADMIN_ALLOWED_EMAILS and (user.email or "").strip().lower() not in ADMIN_ALLOWED_EMAILS:
        raise HTTPException(status_code=403, detail="Admin access denied")

    return user


def _ai_queue_depth_metrics() -> dict:
    queue = _ai_queue()
    started_registry = StartedJobRegistry(name=queue.name, connection=queue.connection)
    failed_registry = FailedJobRegistry(name=queue.name, connection=queue.connection)
    return {
        "queue_name": queue.name,
        "queued_count": queue.count,
        "started_count": len(started_registry),
        "failed_registry_count": len(failed_registry),
    }


def _read_worker_heartbeats() -> list[dict]:
    connection = _redis_connection()
    keys = connection.keys("ai_worker:*:heartbeat")
    heartbeats: list[dict] = []
    for key in keys:
        decoded_key = key.decode("utf-8") if isinstance(key, bytes) else str(key)
        ttl = int(connection.ttl(key))
        stale = ttl <= 0 or ttl < max(1, AI_WORKER_HEARTBEAT_STALE_SECONDS // 2)
        heartbeats.append(
            {
                "worker_key": decoded_key,
                "ttl_seconds": max(ttl, -1),
                "stale": stale,
            }
        )

    heartbeats.sort(key=lambda item: item["worker_key"])
    return heartbeats


def _parse_cors_origins(raw_value: str):
    if not raw_value.strip() or raw_value.strip() == "*":
        return [], True

    origins = [origin.strip() for origin in raw_value.split(",") if origin.strip()]
    return origins, False


def _hash_reset_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _build_reset_link(reset_token: str) -> str:
    base = FRONTEND_BASE_URL.rstrip("/")
    if FRONTEND_ROUTE_MODE == "query":
        return f"{base}/?reset_token={reset_token}"
    if FRONTEND_ROUTE_MODE == "path":
        return f"{base}/reset-password?token={reset_token}"
    return f"{base}/#/reset-password?token={reset_token}"


def _send_reset_email(recipient_email: str, reset_token: str) -> bool:
    if not SMTP_HOST or not SMTP_FROM:
        return False

    reset_link = _build_reset_link(reset_token)
    msg = EmailMessage()
    msg["Subject"] = "Calm Clarity Password Reset"
    msg["From"] = SMTP_FROM
    msg["To"] = recipient_email
    msg.set_content(
        "We received a request to reset your Calm Clarity password.\n\n"
        f"Use this link to reset your password (expires in {RESET_TOKEN_EXPIRE_MINUTES} minutes):\n"
        f"{reset_link}\n\n"
        "If you didn't request this, you can safely ignore this email."
    )

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as smtp:
            if SMTP_USE_TLS:
                smtp.starttls()
            if SMTP_USERNAME and SMTP_PASSWORD:
                smtp.login(SMTP_USERNAME, SMTP_PASSWORD)
            smtp.send_message(msg)
        return True
    except Exception:
        return False


def _provider_candidates() -> list[str]:
    if AI_PROVIDER == "groq":
        return ["groq"]
    if AI_PROVIDER == "gemini":
        return ["gemini"]
    if AI_PROVIDER == "openai":
        return ["openai"]
    return ["groq", "gemini", "openai"]


def _provider_model_name(provider: str) -> str:
    if provider == "groq":
        return GROQ_MODEL
    if provider == "gemini":
        return GEMINI_MODEL
    return OPENAI_MODEL


def _run_entry_ai(payload: schemas.AIAnalyzeEntryRequest) -> tuple[schemas.AIAnalyzeEntryResponse, str, str]:
    for provider in _provider_candidates():
        try:
            if provider == "groq" and GROQ_API_KEY.strip():
                return _groq_ai_reflection(payload), "groq", GROQ_MODEL
            if provider == "gemini" and GEMINI_API_KEY.strip():
                return _gemini_ai_reflection(payload), "gemini", GEMINI_MODEL
            if provider == "openai" and OPENAI_API_KEY.strip():
                return _openai_ai_reflection(payload), "openai", OPENAI_MODEL
        except Exception:
            continue

    fallback = _rule_based_ai_reflection(payload)
    return fallback, "rule_based", "deterministic"


def _run_weekly_ai(payload: schemas.AIWeeklyInsightsRequest) -> tuple[schemas.AIWeeklyInsightsResponse, str, str]:
    for provider in _provider_candidates():
        try:
            if provider == "groq" and GROQ_API_KEY.strip():
                return _groq_weekly_insights(payload), "groq", GROQ_MODEL
            if provider == "gemini" and GEMINI_API_KEY.strip():
                return _gemini_weekly_insights(payload), "gemini", GEMINI_MODEL
            if provider == "openai" and OPENAI_API_KEY.strip():
                return _openai_weekly_insights(payload), "openai", OPENAI_MODEL
        except Exception:
            continue

    fallback = _rule_based_weekly_insights(payload)
    return fallback, "rule_based", "deterministic"


def _moderation_block_entry() -> dict:
    return {
        "ai_summary": "Your safety matters most right now.",
        "ai_action_items": [
            "Pause and take a slow breath.",
            "Reach out to a trusted person immediately.",
        ],
        "ai_mood_explanation": "Your message includes language that may indicate a serious safety risk.",
        "ai_followup_prompt": "Would you like help contacting immediate support resources?",
        "safety_flag": True,
        "crisis_resources": _crisis_resources(),
    }


def _moderation_block_weekly() -> dict:
    return {
        "weekly_summary": "Your entries include language that may indicate immediate emotional risk.",
        "key_patterns": ["Safety support is prioritized before coaching analysis."],
        "coaching_priorities": ["Contact immediate support resources now."],
        "next_week_prompt": "Would you like to connect with crisis support now?",
        "memory_snippets_used": [],
        "safety_flag": True,
        "crisis_resources": _crisis_resources(),
    }


def _process_ai_job(job_id: str) -> None:
    db = SessionLocal()
    try:
        job = db.query(models.AIJob).filter(models.AIJob.id == job_id).first()
        if not job:
            return

        if job.status in {"completed", "blocked", "failed"}:
            return

        job.status = "processing"
        job.attempts = min(job.max_attempts, (job.attempts or 0) + 1)
        job.updated_at = _utc_now()
        db.commit()

        payload_data = json.loads(job.payload_json)
        user_id = job.user_id
        request_type = job.job_type
        input_chars = len(job.payload_json)
        try:
            if request_type == "analyze_entry":
                payload = schemas.AIAnalyzeEntryRequest(**payload_data)
                moderation_text = _entry_moderation_text(payload)
                if len(payload.transcript or "") > AI_MAX_TRANSCRIPT_CHARS:
                    raise ValueError("Transcript exceeds max allowed length")
                if _contains_self_harm_risk(moderation_text):
                    result = _moderation_block_entry()
                    provider = "moderation"
                    model = "safety_rule"
                    job.status = "blocked"
                else:
                    ai_result, provider, model = _run_entry_ai(payload)
                    result = ai_result.model_dump()
                    job.status = "completed"

            elif request_type == "weekly_insights":
                payload = schemas.AIWeeklyInsightsRequest(**payload_data)
                moderation_text = _weekly_moderation_text(payload)
                if _contains_self_harm_risk(moderation_text):
                    result = _moderation_block_weekly()
                    provider = "moderation"
                    model = "safety_rule"
                    job.status = "blocked"
                else:
                    ai_result, provider, model = _run_weekly_ai(payload)
                    result = ai_result.model_dump()
                    job.status = "completed"
            else:
                raise ValueError("Unknown job type")

            result_json = json.dumps(result)
            job.result_json = result_json
            job.provider_used = provider
            job.model_used = model
            job.prompt_version = AI_PROMPT_VERSION
            job.error_message = None
            job.completed_at = _utc_now()
            job.updated_at = _utc_now()

            _log_ai_request(
                db,
                user_id=user_id,
                request_type=request_type,
                status=job.status,
                provider=provider,
                model=model,
                job_id=job.id,
                input_chars=input_chars,
                output_chars=len(result_json),
            )
            db.commit()
            return

        except Exception as error:
            last_error = str(error)[:500]
            job.error_message = last_error
            job.updated_at = _utc_now()

            if job.attempts >= job.max_attempts:
                job.status = "failed"
                job.completed_at = _utc_now()
                _log_ai_request(
                    db,
                    user_id=user_id,
                    request_type=request_type,
                    status="failed",
                    provider=job.provider_used,
                    model=job.model_used,
                    job_id=job.id,
                    input_chars=input_chars,
                    output_chars=0,
                    error_message=job.error_message,
                )
                db.commit()
                return

            job.status = "queued"
            db.commit()
            raise
    finally:
        db.close()


def _google_headers(access_token: str) -> dict:
    return {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }


def _google_calendar_connected(access_token: str) -> bool:
    response = requests.get(
        "https://www.googleapis.com/calendar/v3/users/me/calendarList",
        headers=_google_headers(access_token),
        params={"maxResults": 1},
        timeout=12,
    )
    return response.status_code == 200


def _map_calendar_event(item: dict) -> schemas.GoogleCalendarEventOut:
    start_iso = (item.get("start", {}) or {}).get("dateTime") or (item.get("start", {}) or {}).get("date")
    end_iso = (item.get("end", {}) or {}).get("dateTime") or (item.get("end", {}) or {}).get("date")
    return schemas.GoogleCalendarEventOut(
        id=item.get("id", ""),
        summary=item.get("summary", "Untitled"),
        status=item.get("status"),
        html_link=item.get("htmlLink"),
        start_iso=start_iso,
        end_iso=end_iso,
    )


def _extract_event_timezone(item: dict) -> str:
    start = item.get("start", {}) or {}
    end = item.get("end", {}) or {}
    return start.get("timeZone") or end.get("timeZone") or "UTC"


def _get_or_create_google_sync_state(db: Session, user_id: int) -> models.GoogleCalendarSyncState:
    state = db.query(models.GoogleCalendarSyncState).filter(
        models.GoogleCalendarSyncState.user_id == user_id,
    ).first()
    if state is not None:
        return state

    now = _utc_now()
    state = models.GoogleCalendarSyncState(
        user_id=user_id,
        auto_sync_enabled=1,
        sync_interval_minutes=max(1, GOOGLE_CALENDAR_SYNC_DEFAULT_INTERVAL_MINUTES),
        last_sync_at=None,
        last_error=None,
        pull_cursor_iso=None,
        updated_at=now,
    )
    db.add(state)
    db.flush()
    return state


def _upsert_google_event_mirror(
    db: Session,
    *,
    user_id: int,
    item: dict,
    source: str,
) -> models.GoogleCalendarEventMirror:
    external_event_id = (item.get("id") or "").strip() or None
    private_props = ((item.get("extendedProperties") or {}).get("private") or {})
    client_event_id = (private_props.get("calm_client_event_id") or "").strip() or None

    mirror = None
    if external_event_id:
        mirror = db.query(models.GoogleCalendarEventMirror).filter(
            models.GoogleCalendarEventMirror.user_id == user_id,
            models.GoogleCalendarEventMirror.external_event_id == external_event_id,
        ).first()

    if mirror is None and client_event_id:
        mirror = db.query(models.GoogleCalendarEventMirror).filter(
            models.GoogleCalendarEventMirror.user_id == user_id,
            models.GoogleCalendarEventMirror.client_event_id == client_event_id,
        ).first()

    now = _utc_now()
    if mirror is None:
        mirror = models.GoogleCalendarEventMirror(
            user_id=user_id,
            source=source,
            created_at=now,
            updated_at=now,
        )
        db.add(mirror)

    start_iso = (item.get("start", {}) or {}).get("dateTime") or (item.get("start", {}) or {}).get("date")
    end_iso = (item.get("end", {}) or {}).get("dateTime") or (item.get("end", {}) or {}).get("date")
    status_value = (item.get("status") or "confirmed").strip().lower()

    mirror.client_event_id = client_event_id or mirror.client_event_id
    mirror.external_event_id = external_event_id or mirror.external_event_id
    mirror.summary = (item.get("summary") or "Untitled").strip() or "Untitled"
    mirror.description = item.get("description")
    mirror.status = status_value
    mirror.html_link = item.get("htmlLink")
    mirror.start_iso = start_iso
    mirror.end_iso = end_iso
    mirror.timezone = _extract_event_timezone(item)
    mirror.etag = item.get("etag")
    mirror.updated_remote_iso = item.get("updated")
    mirror.source = source
    mirror.deleted = 1 if status_value == "cancelled" else 0
    mirror.updated_at = now
    return mirror


def _mirror_to_event_schema(mirror: models.GoogleCalendarEventMirror) -> schemas.GoogleCalendarEventOut:
    return schemas.GoogleCalendarEventOut(
        id=(mirror.external_event_id or mirror.client_event_id or ""),
        summary=mirror.summary or "Untitled",
        status=mirror.status,
        html_link=mirror.html_link,
        start_iso=mirror.start_iso,
        end_iso=mirror.end_iso,
    )


def _calendar_pull_sync(
    db: Session,
    *,
    user_id: int,
    access_token: str,
    state: models.GoogleCalendarSyncState,
) -> tuple[int, str | None]:
    pulled_count = 0
    max_updated = state.pull_cursor_iso
    page_token = None

    while True:
        params = {
            "singleEvents": "true",
            "showDeleted": "true",
            "maxResults": 100,
        }
        if state.pull_cursor_iso:
            params["updatedMin"] = state.pull_cursor_iso
        else:
            params["timeMin"] = (datetime.utcnow() - timedelta(days=90)).isoformat() + "Z"
        if page_token:
            params["pageToken"] = page_token

        response = requests.get(
            "https://www.googleapis.com/calendar/v3/calendars/primary/events",
            headers=_google_headers(access_token),
            params=params,
            timeout=20,
        )
        if response.status_code >= 400:
            raise HTTPException(status_code=400, detail="Failed to sync Google Calendar events")

        data = response.json()
        for item in data.get("items", []):
            _upsert_google_event_mirror(db, user_id=user_id, item=item, source="google")
            pulled_count += 1
            updated_value = (item.get("updated") or "").strip()
            if updated_value and (max_updated is None or updated_value > max_updated):
                max_updated = updated_value

        page_token = data.get("nextPageToken")
        if not page_token:
            break

    return pulled_count, max_updated


def _queue_local_calendar_change(
    db: Session,
    *,
    user_id: int,
    change: schemas.GoogleCalendarLocalChange,
) -> None:
    action = (change.action or "").strip().lower()
    if action not in {"create", "update", "delete"}:
        raise HTTPException(status_code=400, detail="Invalid local change action")

    now = _utc_now()
    pending = models.GoogleCalendarPendingChange(
        id=str(uuid.uuid4()),
        user_id=user_id,
        action=action,
        client_event_id=(change.client_event_id or "").strip() or None,
        external_event_id=(change.external_event_id or "").strip() or None,
        payload_json=json.dumps(change.model_dump()),
        status="pending",
        error_message=None,
        created_at=now,
        updated_at=now,
    )
    db.add(pending)


def _build_google_event_payload(payload: dict, client_event_id: str | None) -> dict:
    timezone = (payload.get("timezone") or "UTC").strip() or "UTC"
    body = {
        "summary": (payload.get("summary") or "Untitled").strip() or "Untitled",
        "description": payload.get("description") or "",
        "start": {
            "dateTime": payload.get("start_iso"),
            "timeZone": timezone,
        },
        "end": {
            "dateTime": payload.get("end_iso"),
            "timeZone": timezone,
        },
    }
    if client_event_id:
        body["extendedProperties"] = {
            "private": {"calm_client_event_id": client_event_id},
        }
    return body


def _process_calendar_push_queue(
    db: Session,
    *,
    user_id: int,
    access_token: str,
) -> tuple[int, int]:
    pending_rows = db.query(models.GoogleCalendarPendingChange).filter(
        models.GoogleCalendarPendingChange.user_id == user_id,
        models.GoogleCalendarPendingChange.status == "pending",
    ).order_by(models.GoogleCalendarPendingChange.created_at.asc()).all()

    pushed_count = 0
    failed_count = 0
    now = _utc_now()

    for row in pending_rows:
        try:
            payload_data = json.loads(row.payload_json or "{}")
        except Exception:
            payload_data = {}

        action = (row.action or "").strip().lower()
        client_event_id = (row.client_event_id or "").strip() or None
        external_event_id = (row.external_event_id or "").strip() or None

        if not external_event_id and client_event_id:
            mirror = db.query(models.GoogleCalendarEventMirror).filter(
                models.GoogleCalendarEventMirror.user_id == user_id,
                models.GoogleCalendarEventMirror.client_event_id == client_event_id,
            ).first()
            if mirror and (mirror.external_event_id or "").strip():
                external_event_id = mirror.external_event_id.strip()

        try:
            if action == "create":
                response = requests.post(
                    "https://www.googleapis.com/calendar/v3/calendars/primary/events",
                    headers=_google_headers(access_token),
                    json=_build_google_event_payload(payload_data, client_event_id),
                    timeout=20,
                )
                if response.status_code >= 400:
                    raise HTTPException(status_code=400, detail=response.text[:220])
                _upsert_google_event_mirror(db, user_id=user_id, item=response.json(), source="app")

            elif action == "update":
                if not external_event_id:
                    raise HTTPException(status_code=400, detail="Missing event id for update")
                response = requests.patch(
                    f"https://www.googleapis.com/calendar/v3/calendars/primary/events/{external_event_id}",
                    headers=_google_headers(access_token),
                    json=_build_google_event_payload(payload_data, client_event_id),
                    timeout=20,
                )
                if response.status_code >= 400:
                    raise HTTPException(status_code=400, detail=response.text[:220])
                _upsert_google_event_mirror(db, user_id=user_id, item=response.json(), source="app")

            elif action == "delete":
                if not external_event_id:
                    raise HTTPException(status_code=400, detail="Missing event id for delete")
                response = requests.delete(
                    f"https://www.googleapis.com/calendar/v3/calendars/primary/events/{external_event_id}",
                    headers=_google_headers(access_token),
                    timeout=20,
                )
                if response.status_code >= 400 and response.status_code != 410:
                    raise HTTPException(status_code=400, detail=response.text[:220])
                mirror = db.query(models.GoogleCalendarEventMirror).filter(
                    models.GoogleCalendarEventMirror.user_id == user_id,
                    models.GoogleCalendarEventMirror.external_event_id == external_event_id,
                ).first()
                if mirror is not None:
                    mirror.deleted = 1
                    mirror.status = "cancelled"
                    mirror.updated_at = now

            row.status = "applied"
            row.error_message = None
            row.updated_at = now
            pushed_count += 1
        except Exception as error:
            row.status = "failed"
            row.error_message = str(error)[:400]
            row.updated_at = now
            failed_count += 1

    return pushed_count, failed_count

Base.metadata.create_all(bind=engine)
_ensure_user_active_column()

app = FastAPI(title="Calm Clarity Backend")


@app.middleware("http")
async def observability_http_middleware(request: Request, call_next):
    started = time.perf_counter()
    status_code = 500
    try:
        response = await call_next(request)
        status_code = int(response.status_code)
        return response
    except Exception:
        status_code = 500
        raise
    finally:
        duration_ms = (time.perf_counter() - started) * 1000.0
        _obs_record(request.url.path, status_code, duration_ms)

cors_origins, _ = _parse_cors_origins(CORS_ALLOW_ORIGINS)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_origin_regex=LOCAL_DEV_ORIGIN_REGEX,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/signup", response_model=schemas.Token)
def signup(user: schemas.UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(models.User).filter(models.User.email == user.email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    hashed_pwd = auth.get_password_hash(user.password)
    new_user = models.User(name=user.name, email=user.email, hashed_password=hashed_pwd)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    access_token = auth.create_access_token(data={"sub": new_user.email})
    return {"access_token": access_token, "token_type": "bearer", "user": new_user}

@app.post("/login", response_model=schemas.Token)
def login(user_credentials: schemas.UserLogin, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == user_credentials.email).first()
    if not user or not auth.verify_password(user_credentials.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )
    if int(user.is_active or 0) != 1:
        raise HTTPException(status_code=403, detail="Account is suspended")
    
    access_token = auth.create_access_token(data={"sub": user.email})
    return {"access_token": access_token, "token_type": "bearer", "user": user}

@app.post("/update_integrations", response_model=schemas.UserOut)
def update_integrations(email: str, google: int, apple: int, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    user.google_calendar_connected = google
    user.apple_health_connected = apple
    db.commit()
    db.refresh(user)
    return user

@app.post("/forgot-password", response_model=schemas.ForgotPasswordResponse)
def forgot_password(payload: schemas.ForgotPasswordRequest, db: Session = Depends(get_db)):
    generic_message = "If an account with that email exists, a password reset link has been sent."
    user = db.query(models.User).filter(models.User.email == payload.email).first()
    if not user:
        return {"message": generic_message, "delivery": "email"}

    now = datetime.utcnow()
    db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.user_id == user.id,
        models.PasswordResetToken.used_at.is_(None),
    ).update({"used_at": now}, synchronize_session=False)

    raw_token = secrets.token_urlsafe(32)
    reset_link = _build_reset_link(raw_token)
    token_record = models.PasswordResetToken(
        user_id=user.id,
        token_hash=_hash_reset_token(raw_token),
        created_at=now,
        expires_at=now + timedelta(minutes=RESET_TOKEN_EXPIRE_MINUTES),
        used_at=None,
    )
    db.add(token_record)
    db.commit()

    email_sent = _send_reset_email(user.email, raw_token)

    if APP_ENV.lower() == "development" and not email_sent:
        return {
            "message": "Email not sent because SMTP is not configured. Use the temporary reset token/link below for local testing.",
            "reset_token": raw_token,
            "reset_link": reset_link,
            "delivery": "dev_link",
        }

    return {"message": generic_message, "delivery": "email"}


@app.post("/reset-password", response_model=schemas.MessageResponse)
def reset_password(payload: schemas.ResetPasswordRequest, db: Session = Depends(get_db)):
    if len(payload.new_password.strip()) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters long")

    now = datetime.utcnow()
    token_hash = _hash_reset_token(payload.token)
    token_record = db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.token_hash == token_hash,
        models.PasswordResetToken.used_at.is_(None),
        models.PasswordResetToken.expires_at > now,
    ).first()

    if not token_record:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user = db.query(models.User).filter(models.User.id == token_record.user_id).first()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid reset request")

    user.hashed_password = auth.get_password_hash(payload.new_password)
    token_record.used_at = now
    db.commit()

    return {"message": "Password reset successful. You can now sign in with your new password."}

@app.post("/refresh", response_model=schemas.Token)
def refresh_token(authorization: str = Header(None), db: Session = Depends(get_db)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
        
    token = authorization.split(" ")[1]
    
    try:
        payload = auth.jwt.decode(token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM], options={"verify_signature": False})
        email: str = payload.get("sub")
        if email is None:
            raise HTTPException(status_code=401, detail="Invalid token")

        user = db.query(models.User).filter(models.User.email == email).first()
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        if int(user.is_active or 0) != 1:
            raise HTTPException(status_code=403, detail="Account is suspended")
            
        # Create a new token
        access_token = auth.create_access_token(data={"sub": email})
        return {"access_token": access_token, "token_type": "bearer", "user": user}
    except Exception as e:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

@app.post("/auth/google", response_model=schemas.Token)
def google_auth(token_data: schemas.SocialAuth, db: Session = Depends(get_db)):
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=500, detail="Server misconfiguration: GOOGLE_CLIENT_ID is missing")

    try:
        # Verify with actual Client ID from env
        id_info = id_token.verify_oauth2_token(
            token_data.token, google_requests.Request(), GOOGLE_CLIENT_ID
        )

        email = id_info['email']
        name = id_info.get('name', '')

        # Check if user exists
        user = db.query(models.User).filter(models.User.email == email).first()
        if not user:
            # Create new user without password (social only)
            user = models.User(email=email, name=name, hashed_password="")
            db.add(user)
            db.commit()
            db.refresh(user)
        if int(user.is_active or 0) != 1:
            raise HTTPException(status_code=403, detail="Account is suspended")

        access_token = auth.create_access_token(data={"sub": user.email})
        return {"access_token": access_token, "token_type": "bearer", "user": user}

    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid Google token")


@app.post("/integrations/google-calendar/connect", response_model=schemas.MessageResponse)
def connect_google_calendar(
    payload: schemas.GoogleCalendarAccessTokenRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    if not _google_calendar_connected(payload.access_token):
        raise HTTPException(status_code=400, detail="Invalid Google Calendar access token")

    user.google_calendar_connected = 1
    state = _get_or_create_google_sync_state(db, user.id)
    state.last_error = None
    state.updated_at = _utc_now()
    db.commit()
    return {"message": "Google Calendar connected"}


@app.post("/integrations/google-calendar/disconnect", response_model=schemas.MessageResponse)
def disconnect_google_calendar(
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    user.google_calendar_connected = 0
    state = db.query(models.GoogleCalendarSyncState).filter(
        models.GoogleCalendarSyncState.user_id == user.id,
    ).first()
    if state is not None:
        state.pull_cursor_iso = None
        state.last_sync_at = None
        state.last_error = None
        state.updated_at = _utc_now()
    db.commit()
    return {"message": "Google Calendar disconnected"}


@app.post("/integrations/google-calendar/events", response_model=schemas.GoogleCalendarEventsResponse)
def list_google_calendar_events(
    payload: schemas.GoogleCalendarAccessTokenRequest,
    user: models.User = Depends(_get_current_user),
):
    response = requests.get(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
        headers=_google_headers(payload.access_token),
        params={
            "singleEvents": "true",
            "orderBy": "startTime",
            "timeMin": datetime.utcnow().isoformat() + "Z",
            "maxResults": 10,
        },
        timeout=12,
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=400, detail="Failed to fetch Google Calendar events")

    data = response.json()
    items = data.get("items", [])
    events = [_map_calendar_event(item) for item in items]
    return {
        "connected": bool(user.google_calendar_connected),
        "events": events,
    }


@app.post("/integrations/google-calendar/events/create", response_model=schemas.GoogleCalendarEventOut)
def create_google_calendar_event(
    payload: schemas.GoogleCalendarEventCreateRequest,
    _: models.User = Depends(_get_current_user),
):
    event_payload = {
        "summary": payload.summary,
        "description": payload.description or "",
        "start": {
            "dateTime": payload.start_iso,
            "timeZone": payload.timezone or "UTC",
        },
        "end": {
            "dateTime": payload.end_iso,
            "timeZone": payload.timezone or "UTC",
        },
    }

    response = requests.post(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
        headers=_google_headers(payload.access_token),
        json=event_payload,
        timeout=12,
    )
    if response.status_code >= 400:
        raise HTTPException(status_code=400, detail="Failed to create Google Calendar event")

    return _map_calendar_event(response.json())


@app.get(
    "/integrations/google-calendar/sync/status",
    response_model=schemas.GoogleCalendarSyncStatusResponse,
)
def get_google_calendar_sync_status(
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    state = _get_or_create_google_sync_state(db, user.id)
    pending_count = db.query(models.GoogleCalendarPendingChange).filter(
        models.GoogleCalendarPendingChange.user_id == user.id,
        models.GoogleCalendarPendingChange.status == "pending",
    ).count()
    db.commit()
    return {
        "connected": bool(user.google_calendar_connected),
        "auto_sync_enabled": bool(state.auto_sync_enabled),
        "sync_interval_minutes": int(state.sync_interval_minutes or GOOGLE_CALENDAR_SYNC_DEFAULT_INTERVAL_MINUTES),
        "last_sync_at": state.last_sync_at.isoformat() if state.last_sync_at else None,
        "last_error": state.last_error,
        "pending_count": int(pending_count),
    }


@app.put(
    "/integrations/google-calendar/sync/settings",
    response_model=schemas.GoogleCalendarSyncStatusResponse,
)
def update_google_calendar_sync_settings(
    payload: schemas.GoogleCalendarSyncSettingsRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    state = _get_or_create_google_sync_state(db, user.id)
    state.auto_sync_enabled = 1 if payload.auto_sync_enabled else 0
    state.sync_interval_minutes = max(1, min(int(payload.sync_interval_minutes), 60))
    state.updated_at = _utc_now()
    db.commit()

    pending_count = db.query(models.GoogleCalendarPendingChange).filter(
        models.GoogleCalendarPendingChange.user_id == user.id,
        models.GoogleCalendarPendingChange.status == "pending",
    ).count()
    return {
        "connected": bool(user.google_calendar_connected),
        "auto_sync_enabled": bool(state.auto_sync_enabled),
        "sync_interval_minutes": int(state.sync_interval_minutes),
        "last_sync_at": state.last_sync_at.isoformat() if state.last_sync_at else None,
        "last_error": state.last_error,
        "pending_count": int(pending_count),
    }


@app.post(
    "/integrations/google-calendar/sync/run",
    response_model=schemas.GoogleCalendarSyncRunResponse,
)
def run_google_calendar_sync(
    payload: schemas.GoogleCalendarSyncRunRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    if not bool(user.google_calendar_connected):
        raise HTTPException(status_code=400, detail="Google Calendar is not connected")
    if not _google_calendar_connected(payload.access_token):
        raise HTTPException(status_code=400, detail="Invalid Google Calendar access token")

    now = _utc_now()
    state = _get_or_create_google_sync_state(db, user.id)
    state.last_error = None

    for change in payload.local_changes or []:
        _queue_local_calendar_change(db, user_id=user.id, change=change)

    pulled_count = 0
    pushed_count = 0
    failed_count = 0

    try:
        pushed_count, failed_count = _process_calendar_push_queue(
            db,
            user_id=user.id,
            access_token=payload.access_token,
        )
        pulled_count, next_cursor = _calendar_pull_sync(
            db,
            user_id=user.id,
            access_token=payload.access_token,
            state=state,
        )
        state.pull_cursor_iso = next_cursor or state.pull_cursor_iso
        state.last_sync_at = now
        state.updated_at = now
    except Exception as error:
        state.last_error = str(error)[:400]
        state.updated_at = now
        db.commit()
        raise

    db.commit()

    events_rows = db.query(models.GoogleCalendarEventMirror).filter(
        models.GoogleCalendarEventMirror.user_id == user.id,
        models.GoogleCalendarEventMirror.deleted == 0,
    ).order_by(models.GoogleCalendarEventMirror.updated_at.desc()).limit(100).all()
    pending_count = db.query(models.GoogleCalendarPendingChange).filter(
        models.GoogleCalendarPendingChange.user_id == user.id,
        models.GoogleCalendarPendingChange.status == "pending",
    ).count()

    return {
        "synced_at": now.isoformat(),
        "pulled_count": int(pulled_count),
        "pushed_count": int(pushed_count),
        "failed_count": int(failed_count),
        "pending_count": int(pending_count),
        "events": [_mirror_to_event_schema(row).model_dump() for row in events_rows],
    }


@app.post("/notifications/devices/register", response_model=schemas.MessageResponse)
def register_notification_device(
    payload: schemas.NotificationDeviceRegisterRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    now = _utc_now()
    device = db.query(models.NotificationDevice).filter(
        models.NotificationDevice.user_id == user.id,
        models.NotificationDevice.device_id == payload.device_id,
    ).first()

    if device is None:
        device = models.NotificationDevice(
            user_id=user.id,
            device_id=payload.device_id.strip(),
            platform=payload.platform.strip().lower(),
            push_token=payload.push_token.strip(),
            push_enabled=1 if payload.push_enabled else 0,
            app_version=(payload.app_version or "").strip() or None,
            created_at=now,
            updated_at=now,
            last_seen_at=now,
        )
        db.add(device)
    else:
        device.platform = payload.platform.strip().lower()
        device.push_token = payload.push_token.strip()
        device.push_enabled = 1 if payload.push_enabled else 0
        device.app_version = (payload.app_version or "").strip() or None
        device.updated_at = now
        device.last_seen_at = now

    db.commit()
    return {"message": "Notification device registered"}


@app.get("/notifications/preferences", response_model=schemas.NotificationPreferencesResponse)
def get_notification_preferences(
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    prefs = _get_or_create_notification_preferences(db, user.id)
    db.commit()
    return _prefs_to_schema(prefs)


@app.put("/notifications/preferences", response_model=schemas.NotificationPreferencesResponse)
def update_notification_preferences(
    payload: schemas.NotificationPreferencesRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    if payload.daily_reminder_hour < 0 or payload.daily_reminder_hour > 23:
        raise HTTPException(status_code=400, detail="daily_reminder_hour must be between 0 and 23")
    if payload.daily_reminder_minute < 0 or payload.daily_reminder_minute > 59:
        raise HTTPException(status_code=400, detail="daily_reminder_minute must be between 0 and 59")

    prefs = _get_or_create_notification_preferences(db, user.id)
    prefs.notifications_enabled = 1 if payload.notifications_enabled else 0
    prefs.push_enabled = 1 if payload.push_enabled else 0
    prefs.daily_reminder_enabled = 1 if payload.daily_reminder_enabled else 0
    prefs.daily_reminder_hour = int(payload.daily_reminder_hour)
    prefs.daily_reminder_minute = int(payload.daily_reminder_minute)
    prefs.timezone = payload.timezone.strip() or "UTC"
    prefs.updated_at = _utc_now()
    db.commit()
    db.refresh(prefs)
    return _prefs_to_schema(prefs)


@app.post("/notifications/trigger", response_model=schemas.NotificationTriggerResponse)
def trigger_notification(
    payload: schemas.NotificationTriggerRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    if not payload.title.strip() or not payload.body.strip() or not payload.event_type.strip():
        raise HTTPException(status_code=400, detail="event_type, title and body are required")

    result = _dispatch_push_notification(
        db,
        user_id=user.id,
        event_type=payload.event_type.strip(),
        title=payload.title.strip(),
        body=payload.body.strip(),
        data=payload.data or {},
    )
    db.commit()
    return result


@app.get("/notifications/health", response_model=schemas.NotificationHealthResponse)
def notification_health(
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    prefs = _get_or_create_notification_preferences(db, user.id)
    stale_cutoff = _stale_device_cutoff()
    devices = db.query(models.NotificationDevice).filter(
        models.NotificationDevice.user_id == user.id,
    ).all()

    active_devices = len([
        device
        for device in devices
        if int(device.push_enabled or 0) == 1 and device.last_seen_at >= stale_cutoff
    ])
    stale_devices = len([device for device in devices if device.last_seen_at < stale_cutoff])
    recent_sent, recent_failed = _notification_delivery_counts(
        db,
        since=_recent_notification_cutoff(),
        user_id=user.id,
    )

    return {
        "generated_at": _utc_now().isoformat(),
        "firebase_configured": bool(FCM_SERVER_KEY.strip()),
        "notifications_enabled": bool(prefs.notifications_enabled),
        "push_enabled": bool(prefs.push_enabled),
        "active_devices": active_devices,
        "stale_devices": stale_devices,
        "recent_sent": recent_sent,
        "recent_failed": recent_failed,
    }


@app.get("/admin/notifications/readiness", response_model=schemas.NotificationReadinessResponse)
def admin_notification_readiness(
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    now = _utc_now()
    checks: list[dict] = []
    stale_cutoff = _stale_device_cutoff()

    all_devices = db.query(models.NotificationDevice).all()
    active_devices = len([
        device
        for device in all_devices
        if int(device.push_enabled or 0) == 1 and device.last_seen_at >= stale_cutoff
    ])
    stale_devices = len([device for device in all_devices if device.last_seen_at < stale_cutoff])

    recent_sent, recent_failed = _notification_delivery_counts(
        db,
        since=_recent_notification_cutoff(),
        user_id=None,
    )

    if FCM_SERVER_KEY.strip():
        checks.append({
            "name": "fcm_server_key",
            "status": "ok",
            "detail": "FCM server key configured",
        })
    else:
        checks.append({
            "name": "fcm_server_key",
            "status": "fail",
            "detail": "FCM_SERVER_KEY is missing",
        })

    if active_devices > 0:
        checks.append({
            "name": "active_device_pool",
            "status": "ok",
            "detail": f"Active devices={active_devices}",
        })
    else:
        checks.append({
            "name": "active_device_pool",
            "status": "warn",
            "detail": "No active push devices registered",
        })

    total_recent = recent_sent + recent_failed
    failure_rate = (recent_failed / total_recent) if total_recent > 0 else 0.0
    if total_recent == 0:
        checks.append({
            "name": "delivery_traffic",
            "status": "warn",
            "detail": "No recent push delivery attempts in monitoring window",
        })
    elif failure_rate >= max(0.0, NOTIFICATION_FAILURE_WARN_RATE):
        checks.append({
            "name": "delivery_failure_rate",
            "status": "warn",
            "detail": (
                f"Failure rate={failure_rate:.2%} "
                f"(warn threshold={max(0.0, NOTIFICATION_FAILURE_WARN_RATE):.2%})"
            ),
        })
    else:
        checks.append({
            "name": "delivery_failure_rate",
            "status": "ok",
            "detail": f"Failure rate={failure_rate:.2%}",
        })

    if any(item["status"] == "fail" for item in checks):
        overall_status = "fail"
    elif any(item["status"] == "warn" for item in checks):
        overall_status = "warn"
    else:
        overall_status = "ok"

    return {
        "generated_at": now.isoformat(),
        "overall_status": overall_status,
        "checks": checks,
        "total_devices": len(all_devices),
        "active_devices": active_devices,
        "stale_devices": stale_devices,
        "recent_sent": recent_sent,
        "recent_failed": recent_failed,
    }


@app.get("/admin/access", response_model=schemas.AdminAccessResponse)
def admin_access_check(
    user: models.User = Depends(_require_admin),
):
    return {
        "is_admin": True,
        "email": user.email,
    }


@app.get("/admin/users/summary", response_model=schemas.AdminUserSummaryResponse)
def admin_users_summary(
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    now = _utc_now()
    today = now.strftime("%Y-%m-%d")
    seven_days_ago = now - timedelta(days=7)

    total_users = db.query(models.User).count()
    users_with_google_calendar = db.query(models.User).filter(
        models.User.google_calendar_connected == 1,
    ).count()
    users_with_apple_health = db.query(models.User).filter(
        models.User.apple_health_connected == 1,
    ).count()

    users_active_last_7_days = db.query(func.count(func.distinct(models.AIRequestLog.user_id))).filter(
        models.AIRequestLog.created_at >= seven_days_ago,
    ).scalar() or 0

    ai_requests_last_7_days = db.query(models.AIRequestLog).filter(
        models.AIRequestLog.created_at >= seven_days_ago,
    ).count()
    ai_requests_today = db.query(models.AIUsageDaily).filter(
        models.AIUsageDaily.usage_date == today,
    ).with_entities(func.coalesce(func.sum(models.AIUsageDaily.request_count), 0)).scalar() or 0

    return {
        "generated_at": now.isoformat(),
        "total_users": int(total_users),
        "users_with_google_calendar": int(users_with_google_calendar),
        "users_with_apple_health": int(users_with_apple_health),
        "users_active_last_7_days": int(users_active_last_7_days),
        "ai_requests_last_7_days": int(ai_requests_last_7_days),
        "ai_requests_today": int(ai_requests_today),
    }


@app.get("/admin/users", response_model=schemas.AdminUserListResponse)
def admin_list_users(
    query: str = "",
    limit: int = 50,
    offset: int = 0,
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    now = _utc_now()
    today = now.strftime("%Y-%m-%d")
    seven_days_ago = now - timedelta(days=7)
    safe_limit = max(1, min(limit, 200))
    safe_offset = max(0, offset)

    base_query = db.query(models.User)
    normalized = query.strip().lower()
    if normalized:
        like = f"%{normalized}%"
        base_query = base_query.filter(
            func.lower(models.User.email).like(like) |
            func.lower(func.coalesce(models.User.name, "")).like(like)
        )

    total = base_query.count()
    users = base_query.order_by(models.User.id.asc()).offset(safe_offset).limit(safe_limit).all()

    user_ids = [user.id for user in users]
    ai_7d_map: dict[int, int] = {}
    ai_today_map: dict[int, int] = {}
    active_device_map: dict[int, int] = {}
    last_seen_map: dict[int, datetime] = {}

    if user_ids:
        rows_7d = db.query(
            models.AIRequestLog.user_id,
            func.count(models.AIRequestLog.id),
        ).filter(
            models.AIRequestLog.user_id.in_(user_ids),
            models.AIRequestLog.created_at >= seven_days_ago,
        ).group_by(models.AIRequestLog.user_id).all()
        ai_7d_map = {int(uid): int(count) for uid, count in rows_7d}

        rows_today = db.query(
            models.AIUsageDaily.user_id,
            func.coalesce(func.sum(models.AIUsageDaily.request_count), 0),
        ).filter(
            models.AIUsageDaily.user_id.in_(user_ids),
            models.AIUsageDaily.usage_date == today,
        ).group_by(models.AIUsageDaily.user_id).all()
        ai_today_map = {int(uid): int(count) for uid, count in rows_today}

        stale_cutoff = _stale_device_cutoff()
        rows_devices = db.query(
            models.NotificationDevice.user_id,
            func.count(models.NotificationDevice.id),
        ).filter(
            models.NotificationDevice.user_id.in_(user_ids),
            models.NotificationDevice.push_enabled == 1,
            models.NotificationDevice.last_seen_at >= stale_cutoff,
        ).group_by(models.NotificationDevice.user_id).all()
        active_device_map = {int(uid): int(count) for uid, count in rows_devices}

        rows_last_seen = db.query(
            models.NotificationDevice.user_id,
            func.max(models.NotificationDevice.last_seen_at),
        ).filter(
            models.NotificationDevice.user_id.in_(user_ids),
        ).group_by(models.NotificationDevice.user_id).all()
        last_seen_map = {int(uid): last_seen for uid, last_seen in rows_last_seen if last_seen is not None}

    return {
        "generated_at": now.isoformat(),
        "total": int(total),
        "limit": int(safe_limit),
        "offset": int(safe_offset),
        "users": [
            {
                "id": int(user.id),
                "name": user.name,
                "email": user.email,
                "is_active": bool(user.is_active),
                "google_calendar_connected": bool(user.google_calendar_connected),
                "apple_health_connected": bool(user.apple_health_connected),
                "ai_requests_last_7_days": int(ai_7d_map.get(user.id, 0)),
                "ai_requests_today": int(ai_today_map.get(user.id, 0)),
                "push_devices_active": int(active_device_map.get(user.id, 0)),
                "last_seen_at": (
                    last_seen_map[user.id].isoformat()
                    if user.id in last_seen_map else None
                ),
                "created_at": None,
            }
            for user in users
        ],
    }


@app.delete("/admin/users/{user_id}", response_model=schemas.AdminUserDeleteResponse)
def admin_delete_user(
    user_id: int,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    if target.id == admin_user.id:
        raise HTTPException(status_code=400, detail="Cannot delete your own admin account")

    db.query(models.PasswordResetToken).filter(models.PasswordResetToken.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AIUsageDaily).filter(models.AIUsageDaily.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AIRequestLog).filter(models.AIRequestLog.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AIJob).filter(models.AIJob.user_id == user_id).delete(synchronize_session=False)
    db.query(models.NotificationDevice).filter(models.NotificationDevice.user_id == user_id).delete(synchronize_session=False)
    db.query(models.NotificationPreference).filter(models.NotificationPreference.user_id == user_id).delete(synchronize_session=False)
    db.query(models.NotificationLog).filter(models.NotificationLog.user_id == user_id).delete(synchronize_session=False)
    db.query(models.GoogleCalendarPendingChange).filter(models.GoogleCalendarPendingChange.user_id == user_id).delete(synchronize_session=False)
    db.query(models.GoogleCalendarEventMirror).filter(models.GoogleCalendarEventMirror.user_id == user_id).delete(synchronize_session=False)
    db.query(models.GoogleCalendarSyncState).filter(models.GoogleCalendarSyncState.user_id == user_id).delete(synchronize_session=False)

    db.delete(target)
    db.commit()

    return {
        "user_id": int(user_id),
        "message": "User and related records deleted",
    }


@app.post("/admin/users/{user_id}/suspend", response_model=schemas.AdminUserStateResponse)
def admin_suspend_user(
    user_id: int,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    if target.id == admin_user.id:
        raise HTTPException(status_code=400, detail="Cannot suspend your own admin account")

    target.is_active = 0
    db.commit()

    return {
        "user_id": int(user_id),
        "is_active": False,
        "message": "User suspended",
    }


@app.post("/admin/users/{user_id}/reactivate", response_model=schemas.AdminUserStateResponse)
def admin_reactivate_user(
    user_id: int,
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    target.is_active = 1
    db.commit()

    return {
        "user_id": int(user_id),
        "is_active": True,
        "message": "User reactivated",
    }


@app.post("/ai/analyze-entry", response_model=schemas.AIAnalyzeEntryResponse)
def analyze_entry(
    payload: schemas.AIAnalyzeEntryRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    if not payload.transcript.strip() and not payload.summary.strip():
        raise HTTPException(status_code=400, detail="Transcript or summary is required")
    if len(payload.transcript or "") > AI_MAX_TRANSCRIPT_CHARS:
        raise HTTPException(status_code=400, detail=f"Transcript too long (max {AI_MAX_TRANSCRIPT_CHARS} chars)")

    _enforce_daily_quota(db, user.id)

    moderation_text = _entry_moderation_text(payload)
    if _contains_self_harm_risk(moderation_text):
        result = schemas.AIAnalyzeEntryResponse(**_moderation_block_entry())
        _dispatch_push_notification(
            db,
            user_id=user.id,
            event_type="safety_checkin",
            title="Support resources available",
            body="If you're in immediate danger, call local emergency services now. In the US/Canada call or text 988.",
            data={"source": "ai_analyze_entry_moderation"},
        )
        _log_ai_request(
            db,
            user_id=user.id,
            request_type="analyze_entry",
            status="blocked",
            provider="moderation",
            model="safety_rule",
            input_chars=len(moderation_text),
            output_chars=len(json.dumps(result.model_dump())),
        )
        db.commit()
        return result

    ai_result, provider_used, model_used = _run_entry_ai(payload)
    if ai_result.safety_flag:
        _dispatch_push_notification(
            db,
            user_id=user.id,
            event_type="safety_checkin",
            title="Take a gentle pause",
            body="Your latest reflection may benefit from extra support. Tap to view your safety resources.",
            data={"source": "ai_analyze_entry_result"},
        )
    _log_ai_request(
        db,
        user_id=user.id,
        request_type="analyze_entry",
        status="completed",
        provider=provider_used,
        model=model_used,
        input_chars=len(moderation_text),
        output_chars=len(json.dumps(ai_result.model_dump())),
    )
    db.commit()
    return ai_result

@app.post("/ai/weekly-insights", response_model=schemas.AIWeeklyInsightsResponse)
def weekly_insights(
    payload: schemas.AIWeeklyInsightsRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_daily_quota(db, user.id)

    moderation_text = _weekly_moderation_text(payload)
    if _contains_self_harm_risk(moderation_text):
        result = schemas.AIWeeklyInsightsResponse(**_moderation_block_weekly())
        _dispatch_push_notification(
            db,
            user_id=user.id,
            event_type="safety_checkin",
            title="We're here for you",
            body="Your weekly reflections mention high-risk language. Reach out to local crisis support if needed.",
            data={"source": "ai_weekly_moderation"},
        )
        _log_ai_request(
            db,
            user_id=user.id,
            request_type="weekly_insights",
            status="blocked",
            provider="moderation",
            model="safety_rule",
            input_chars=len(moderation_text),
            output_chars=len(json.dumps(result.model_dump())),
        )
        db.commit()
        return result

    ai_result, provider_used, model_used = _run_weekly_ai(payload)
    if ai_result.safety_flag:
        _dispatch_push_notification(
            db,
            user_id=user.id,
            event_type="safety_checkin",
            title="Support check-in",
            body="Your weekly insights flagged a concern. Open Calm Clarity for guidance and resources.",
            data={"source": "ai_weekly_result"},
        )
    _log_ai_request(
        db,
        user_id=user.id,
        request_type="weekly_insights",
        status="completed",
        provider=provider_used,
        model=model_used,
        input_chars=len(moderation_text),
        output_chars=len(json.dumps(ai_result.model_dump())),
    )
    db.commit()
    return ai_result


@app.post("/ai/jobs/analyze-entry", response_model=schemas.AIJobCreateResponse)
def enqueue_analyze_entry(
    payload: schemas.AIAnalyzeEntryRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    if len(payload.transcript or "") > AI_MAX_TRANSCRIPT_CHARS:
        raise HTTPException(status_code=400, detail=f"Transcript too long (max {AI_MAX_TRANSCRIPT_CHARS} chars)")

    _enforce_daily_quota(db, user.id)

    now = _utc_now()
    job = models.AIJob(
        id=str(uuid.uuid4()),
        user_id=user.id,
        job_type="analyze_entry",
        status="queued",
        attempts=0,
        max_attempts=AI_JOB_MAX_ATTEMPTS,
        payload_json=json.dumps(payload.model_dump()),
        result_json=None,
        error_message=None,
        provider_used=None,
        model_used=None,
        prompt_version=AI_PROMPT_VERSION,
        created_at=now,
        updated_at=now,
        completed_at=None,
    )
    db.add(job)
    db.commit()

    try:
        _enqueue_ai_job(job.id, job.max_attempts)
    except Exception as error:
        job.error_message = f"Queue unavailable, processing inline: {str(error)[:420]}"
        job.updated_at = _utc_now()
        db.commit()
        try:
            _process_ai_job(job.id)
            db.refresh(job)
        except Exception as inline_error:
            job.status = "failed"
            job.error_message = f"Inline AI processing failed: {str(inline_error)[:420]}"
            job.completed_at = _utc_now()
            job.updated_at = _utc_now()
            db.commit()
            raise HTTPException(status_code=503, detail="AI queue unavailable")

    return {
        "job_id": job.id,
        "status": job.status,
        "queued_at": now.isoformat(),
    }


@app.post("/ai/jobs/weekly-insights", response_model=schemas.AIJobCreateResponse)
def enqueue_weekly_insights(
    payload: schemas.AIWeeklyInsightsRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_daily_quota(db, user.id)

    now = _utc_now()
    job = models.AIJob(
        id=str(uuid.uuid4()),
        user_id=user.id,
        job_type="weekly_insights",
        status="queued",
        attempts=0,
        max_attempts=AI_JOB_MAX_ATTEMPTS,
        payload_json=json.dumps(payload.model_dump()),
        result_json=None,
        error_message=None,
        provider_used=None,
        model_used=None,
        prompt_version=AI_PROMPT_VERSION,
        created_at=now,
        updated_at=now,
        completed_at=None,
    )
    db.add(job)
    db.commit()

    try:
        _enqueue_ai_job(job.id, job.max_attempts)
    except Exception as error:
        job.error_message = f"Queue unavailable, processing inline: {str(error)[:420]}"
        job.updated_at = _utc_now()
        db.commit()
        try:
            _process_ai_job(job.id)
            db.refresh(job)
        except Exception as inline_error:
            job.status = "failed"
            job.error_message = f"Inline AI processing failed: {str(inline_error)[:420]}"
            job.completed_at = _utc_now()
            job.updated_at = _utc_now()
            db.commit()
            raise HTTPException(status_code=503, detail="AI queue unavailable")

    return {
        "job_id": job.id,
        "status": job.status,
        "queued_at": now.isoformat(),
    }


@app.get("/ai/jobs/{job_id}", response_model=schemas.AIJobStatusResponse)
def get_ai_job_status(
    job_id: str,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    job = db.query(models.AIJob).filter(
        models.AIJob.id == job_id,
        models.AIJob.user_id == user.id,
    ).first()
    if not job:
        raise HTTPException(status_code=404, detail="AI job not found")

    now = _utc_now()
    if job.status == "processing":
        age_seconds = (now - job.updated_at).total_seconds()
        if age_seconds >= AI_STALE_PROCESSING_SECONDS:
            if job.attempts < job.max_attempts:
                job.status = "queued"
                job.error_message = f"Recovered stale processing job after {int(age_seconds)}s"
                job.updated_at = now
                db.commit()
                try:
                    _enqueue_ai_job(job.id, job.max_attempts)
                except Exception as error:
                    job.status = "failed"
                    job.error_message = f"Queue unavailable during recovery: {str(error)[:420]}"
                    job.updated_at = _utc_now()
                    job.completed_at = _utc_now()
                    db.commit()
            else:
                job.status = "failed"
                job.error_message = f"Stale processing timeout exceeded ({int(age_seconds)}s)"
                job.updated_at = now
                job.completed_at = now
                db.commit()

            db.refresh(job)

    result_obj = json.loads(job.result_json) if job.result_json else None
    return {
        "job_id": job.id,
        "job_type": job.job_type,
        "status": job.status,
        "attempts": job.attempts,
        "max_attempts": job.max_attempts,
        "error_message": job.error_message,
        "result": result_obj,
        "provider_used": job.provider_used,
        "model_used": job.model_used,
        "prompt_version": job.prompt_version,
        "updated_at": job.updated_at.isoformat(),
    }


@app.get("/ai/queue/health", response_model=schemas.AIQueueHealthResponse)
def get_ai_queue_health(
    _: models.User = Depends(_get_current_user),
):
    try:
        metrics = _ai_queue_depth_metrics()
        return {
            "queue_name": metrics["queue_name"],
            "queued_count": metrics["queued_count"],
            "started_count": metrics["started_count"],
            "failed_count": metrics["failed_registry_count"],
        }
    except Exception as error:
        raise HTTPException(status_code=503, detail=f"Queue health unavailable: {str(error)[:300]}")


@app.get("/admin/ai/ops/dashboard", response_model=schemas.AIOpsDashboardResponse)
def get_admin_ai_ops_dashboard(
    days: int = 7,
    failed_limit: int = 20,
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    window_days = max(1, min(int(days), 90))
    failed_limit = max(1, min(int(failed_limit), 100))

    now = _utc_now()
    window_start = now - timedelta(days=window_days)
    window_start_date = window_start.strftime("%Y-%m-%d")
    today = now.strftime("%Y-%m-%d")

    jobs = db.query(models.AIJob).filter(models.AIJob.created_at >= window_start).all()
    logs = db.query(models.AIRequestLog).filter(models.AIRequestLog.created_at >= window_start).all()
    usage_rows = db.query(models.AIUsageDaily).filter(models.AIUsageDaily.usage_date >= window_start_date).all()

    status_counts = {
        "queued": 0,
        "processing": 0,
        "completed": 0,
        "failed": 0,
        "blocked": 0,
    }
    retry_jobs = 0
    total_retry_attempts = 0
    exhausted_jobs = 0
    blocked_jobs = 0

    for job in jobs:
        normalized_status = (job.status or "").strip().lower()
        if normalized_status in status_counts:
            status_counts[normalized_status] += 1

        attempts = int(job.attempts or 0)
        max_attempts = int(job.max_attempts or 0)
        if attempts > 1:
            retry_jobs += 1
            total_retry_attempts += (attempts - 1)

        if normalized_status == "failed" and max_attempts > 0 and attempts >= max_attempts:
            exhausted_jobs += 1

        if normalized_status == "blocked" or (job.provider_used or "").strip().lower() == "moderation":
            blocked_jobs += 1

    blocked_requests = 0
    for log in logs:
        if (log.status or "").strip().lower() == "blocked" or (log.provider or "").strip().lower() == "moderation":
            blocked_requests += 1

    request_count_by_date = defaultdict(int)
    request_count_by_user = defaultdict(int)
    today_request_count = 0
    today_users = set()

    for row in usage_rows:
        usage_date = (row.usage_date or "").strip()
        request_count = int(row.request_count or 0)
        request_count_by_date[usage_date] += request_count
        request_count_by_user[int(row.user_id)] += request_count
        if usage_date == today:
            today_request_count += request_count
            today_users.add(int(row.user_id))

    window_request_count = sum(request_count_by_date.values())
    window_unique_users = len({uid for uid, count in request_count_by_user.items() if count > 0})

    daily_series = [
        {"usage_date": date, "request_count": count}
        for date, count in sorted(request_count_by_date.items())
    ]

    top_user_rows = sorted(
        request_count_by_user.items(),
        key=lambda item: item[1],
        reverse=True,
    )[:10]
    top_user_ids = [user_id for user_id, _ in top_user_rows]
    user_email_map = {}
    if top_user_ids:
        users = db.query(models.User).filter(models.User.id.in_(top_user_ids)).all()
        user_email_map = {int(user.id): user.email for user in users}

    top_users = [
        {
            "user_id": int(user_id),
            "email": user_email_map.get(int(user_id)),
            "request_count": int(request_count),
        }
        for user_id, request_count in top_user_rows
    ]

    failed_jobs_rows = db.query(models.AIJob).filter(
        models.AIJob.status == "failed",
        models.AIJob.created_at >= window_start,
    ).order_by(models.AIJob.updated_at.desc()).limit(failed_limit).all()
    failed_jobs = [
        {
            "job_id": job.id,
            "user_id": int(job.user_id),
            "job_type": job.job_type,
            "status": job.status,
            "attempts": int(job.attempts or 0),
            "max_attempts": int(job.max_attempts or 0),
            "error_message": job.error_message,
            "provider_used": job.provider_used,
            "model_used": job.model_used,
            "created_at": job.created_at.isoformat(),
            "updated_at": job.updated_at.isoformat(),
        }
        for job in failed_jobs_rows
    ]

    try:
        queue_depth = _ai_queue_depth_metrics()
    except Exception:
        queue_depth = {
            "queue_name": AI_QUEUE_NAME,
            "queued_count": 0,
            "started_count": 0,
            "failed_registry_count": 0,
        }

    return {
        "generated_at": now.isoformat(),
        "window_days": window_days,
        "queue_depth": queue_depth,
        "job_status": {
            "total": len(jobs),
            "queued": status_counts["queued"],
            "processing": status_counts["processing"],
            "completed": status_counts["completed"],
            "failed": status_counts["failed"],
            "blocked": status_counts["blocked"],
        },
        "retries": {
            "jobs_with_retry": retry_jobs,
            "total_retry_attempts": total_retry_attempts,
            "exhausted_jobs": exhausted_jobs,
        },
        "moderation": {
            "blocked_jobs": blocked_jobs,
            "blocked_requests": blocked_requests,
        },
        "quota": {
            "daily_quota_limit": AI_DAILY_QUOTA,
            "today_request_count": today_request_count,
            "today_unique_users": len(today_users),
            "window_request_count": window_request_count,
            "window_unique_users": window_unique_users,
            "daily_series": daily_series,
            "top_users": top_users,
        },
        "failed_jobs": failed_jobs,
    }


@app.get("/admin/ai/ops/dead-letter", response_model=schemas.AIDeadLetterListResponse)
def list_dead_letter_jobs(
    limit: int = 50,
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    limit = max(1, min(int(limit), 200))
    queue = _ai_queue()
    failed_registry = FailedJobRegistry(name=queue.name, connection=queue.connection)

    rows = db.query(models.AIJob).filter(models.AIJob.status == "failed").order_by(
        models.AIJob.updated_at.desc(),
    ).limit(limit).all()

    return {
        "generated_at": _utc_now().isoformat(),
        "queue_name": queue.name,
        "total_failed_jobs": len(failed_registry),
        "jobs": [
            {
                "job_id": job.id,
                "user_id": int(job.user_id),
                "job_type": job.job_type,
                "status": job.status,
                "attempts": int(job.attempts or 0),
                "max_attempts": int(job.max_attempts or 0),
                "error_message": job.error_message,
                "provider_used": job.provider_used,
                "model_used": job.model_used,
                "created_at": job.created_at.isoformat(),
                "updated_at": job.updated_at.isoformat(),
            }
            for job in rows
        ],
    }


@app.post("/admin/ai/ops/dead-letter/{job_id}/requeue", response_model=schemas.AIDeadLetterActionResponse)
def requeue_dead_letter_job(
    job_id: str,
    reset_attempts: bool = False,
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    job = db.query(models.AIJob).filter(models.AIJob.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="AI job not found")

    if job.status not in {"failed", "blocked"}:
        raise HTTPException(status_code=400, detail="Only failed or blocked jobs can be requeued")

    if reset_attempts:
        job.attempts = 0
    elif job.attempts >= job.max_attempts:
        raise HTTPException(
            status_code=400,
            detail="Job exhausted max attempts. Pass reset_attempts=true to requeue.",
        )

    queue = _ai_queue()
    failed_registry = FailedJobRegistry(name=queue.name, connection=queue.connection)
    try:
        failed_registry.remove(job.id, delete_job=False)
    except Exception:
        pass

    try:
        rq_job = Job.fetch(job.id, connection=queue.connection)
        rq_job.delete()
    except Exception:
        pass

    job.status = "queued"
    job.error_message = "Requeued from dead-letter by admin"
    job.updated_at = _utc_now()
    job.completed_at = None
    db.commit()

    _enqueue_ai_job(job.id, job.max_attempts)
    return {
        "job_id": job.id,
        "status": "queued",
        "message": "Job requeued successfully",
    }


@app.get("/admin/ai/ops/reliability/validate", response_model=schemas.AIReliabilityValidationResponse)
def validate_ai_ops_reliability(
    _: models.User = Depends(_require_admin),
):
    now = _utc_now()
    checks: list[dict] = []
    heartbeats: list[dict] = []

    try:
        connection = _redis_connection()
        connection.ping()
        checks.append({"name": "redis_connectivity", "status": "ok", "detail": "Redis ping successful"})
    except Exception as error:
        checks.append({
            "name": "redis_connectivity",
            "status": "fail",
            "detail": f"Redis unavailable: {str(error)[:220]}",
        })
        return {
            "generated_at": now.isoformat(),
            "overall_status": "fail",
            "checks": checks,
            "queue_name": AI_QUEUE_NAME,
            "heartbeat_workers": [],
        }

    queue_depth = _ai_queue_depth_metrics()
    if queue_depth["queued_count"] >= AI_OPS_QUEUE_WARN_DEPTH:
        checks.append({
            "name": "queue_depth",
            "status": "warn",
            "detail": f"Queued jobs={queue_depth['queued_count']} (warn threshold={AI_OPS_QUEUE_WARN_DEPTH})",
        })
    else:
        checks.append({
            "name": "queue_depth",
            "status": "ok",
            "detail": f"Queued jobs={queue_depth['queued_count']}",
        })

    if queue_depth["failed_registry_count"] >= AI_OPS_FAILED_REGISTRY_WARN:
        checks.append({
            "name": "failed_registry",
            "status": "warn",
            "detail": (
                f"Failed registry size={queue_depth['failed_registry_count']} "
                f"(warn threshold={AI_OPS_FAILED_REGISTRY_WARN})"
            ),
        })
    else:
        checks.append({
            "name": "failed_registry",
            "status": "ok",
            "detail": f"Failed registry size={queue_depth['failed_registry_count']}",
        })

    try:
        heartbeats = _read_worker_heartbeats()
    except Exception as error:
        checks.append({
            "name": "worker_heartbeats",
            "status": "fail",
            "detail": f"Could not read worker heartbeats: {str(error)[:220]}",
        })
        heartbeats = []
    else:
        alive_count = len([hb for hb in heartbeats if not hb["stale"]])
        if alive_count < AI_OPS_MIN_HEARTBEAT_WORKERS:
            checks.append({
                "name": "worker_heartbeats",
                "status": "warn",
                "detail": (
                    f"Healthy workers={alive_count}, required minimum={AI_OPS_MIN_HEARTBEAT_WORKERS}"
                ),
            })
        else:
            checks.append({
                "name": "worker_heartbeats",
                "status": "ok",
                "detail": f"Healthy workers={alive_count}",
            })

    if any(item["status"] == "fail" for item in checks):
        overall_status = "fail"
    elif any(item["status"] == "warn" for item in checks):
        overall_status = "warn"
    else:
        overall_status = "ok"

    return {
        "generated_at": now.isoformat(),
        "overall_status": overall_status,
        "checks": checks,
        "queue_name": queue_depth["queue_name"],
        "heartbeat_workers": heartbeats,
    }


@app.get("/admin/observability/metrics")
def admin_observability_metrics(
    _: models.User = Depends(_require_admin),
):
    snapshot = _obs_snapshot()

    lines = [
        f"calm_clarity_http_requests_total {snapshot['total_requests']}",
        f"calm_clarity_http_errors_total {snapshot['total_errors']}",
        f"calm_clarity_http_window_requests {snapshot['window_request_count']}",
        f"calm_clarity_http_window_errors {snapshot['window_error_count']}",
        f"calm_clarity_http_window_error_rate {snapshot['window_error_rate']:.6f}",
        f"calm_clarity_http_window_rps {snapshot['window_rps']:.6f}",
        f"calm_clarity_http_latency_p50_ms {snapshot['latency_p50_ms']:.3f}",
        f"calm_clarity_http_latency_p95_ms {snapshot['latency_p95_ms']:.3f}",
        f"calm_clarity_http_latency_avg_ms {snapshot['latency_avg_ms']:.3f}",
    ]
    for status_code, count in sorted(snapshot["status_counts"].items(), key=lambda item: item[0]):
        lines.append(f'calm_clarity_http_status_total{{code="{status_code}"}} {int(count)}')
    for item in snapshot["top_paths"]:
        lines.append(
            f'calm_clarity_http_path_total{{path="{item["path"]}"}} {int(item["count"])}'
        )

    return PlainTextResponse("\n".join(lines) + "\n")


def _notification_window_counts(db: Session) -> tuple[int, int]:
    sent, failed = _notification_delivery_counts(
        db,
        since=_recent_notification_cutoff(),
        user_id=None,
    )
    return sent, failed


@app.get("/admin/observability/dashboard", response_model=schemas.ObservabilityDashboardResponse)
def admin_observability_dashboard(
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    now = _utc_now()
    snapshot = _obs_snapshot()
    signals: list[dict] = []

    queue_depth = 0
    failed_registry = 0
    try:
        queue_metrics = _ai_queue_depth_metrics()
        queue_depth = int(queue_metrics["queued_count"])
        failed_registry = int(queue_metrics["failed_registry_count"])
    except Exception as error:
        signals.append({
            "signal": "ai_queue_metrics_unavailable",
            "severity": "warn",
            "detail": f"AI queue metrics unavailable: {str(error)[:180]}",
        })

    recent_sent, recent_failed = _notification_window_counts(db)

    if snapshot["window_error_rate"] >= OBS_ERROR_RATE_FAIL:
        signals.append({
            "signal": "http_error_rate_high",
            "severity": "critical",
            "detail": f"HTTP error rate={snapshot['window_error_rate']:.2%}",
        })
    elif snapshot["window_error_rate"] >= OBS_ERROR_RATE_WARN:
        signals.append({
            "signal": "http_error_rate_warn",
            "severity": "warn",
            "detail": f"HTTP error rate={snapshot['window_error_rate']:.2%}",
        })

    if snapshot["latency_p95_ms"] >= OBS_LATENCY_P95_FAIL_MS:
        signals.append({
            "signal": "http_latency_p95_critical",
            "severity": "critical",
            "detail": f"p95 latency={snapshot['latency_p95_ms']:.0f}ms",
        })
    elif snapshot["latency_p95_ms"] >= OBS_LATENCY_P95_WARN_MS:
        signals.append({
            "signal": "http_latency_p95_warn",
            "severity": "warn",
            "detail": f"p95 latency={snapshot['latency_p95_ms']:.0f}ms",
        })

    if queue_depth >= AI_OPS_QUEUE_WARN_DEPTH:
        signals.append({
            "signal": "ai_queue_backlog",
            "severity": "warn",
            "detail": f"Queued jobs={queue_depth}",
        })

    if failed_registry >= AI_OPS_FAILED_REGISTRY_WARN:
        signals.append({
            "signal": "ai_failed_registry_growth",
            "severity": "warn",
            "detail": f"Failed registry jobs={failed_registry}",
        })

    total_notification = recent_sent + recent_failed
    fail_rate = (recent_failed / total_notification) if total_notification > 0 else 0.0
    if total_notification > 0 and fail_rate >= NOTIFICATION_FAILURE_WARN_RATE:
        signals.append({
            "signal": "notification_failure_rate_warn",
            "severity": "warn",
            "detail": f"Push failure rate={fail_rate:.2%}",
        })

    if any(signal["severity"] == "critical" for signal in signals):
        service_status = "critical"
    elif any(signal["severity"] == "warn" for signal in signals):
        service_status = "degraded"
    else:
        service_status = "healthy"

    return {
        "generated_at": now.isoformat(),
        "service_status": service_status,
        "traffic": {
            "window_seconds": max(60, OBS_METRICS_WINDOW_SECONDS),
            "request_count": snapshot["window_request_count"],
            "error_count": snapshot["window_error_count"],
            "error_rate": snapshot["window_error_rate"],
            "requests_per_second": snapshot["window_rps"],
            "latency_p50_ms": snapshot["latency_p50_ms"],
            "latency_p95_ms": snapshot["latency_p95_ms"],
            "latency_avg_ms": snapshot["latency_avg_ms"],
            "top_paths": snapshot["top_paths"],
        },
        "ai_queue_depth": queue_depth,
        "ai_failed_registry": failed_registry,
        "notification_recent_failed": recent_failed,
        "notification_recent_sent": recent_sent,
        "signals": signals,
    }


@app.get("/admin/observability/alerts", response_model=schemas.ObservabilityAlertsResponse)
def admin_observability_alerts(
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    snapshot = _obs_snapshot()
    alerts: list[dict] = []
    now = _utc_now()

    def _status_for(value: float, warn: float, fail: float) -> str:
        if value >= fail:
            return "fail"
        if value >= warn:
            return "warn"
        return "ok"

    error_status = _status_for(snapshot["window_error_rate"], OBS_ERROR_RATE_WARN, OBS_ERROR_RATE_FAIL)
    alerts.append({
        "name": "http_error_rate",
        "status": error_status,
        "detail": f"error_rate={snapshot['window_error_rate']:.2%}",
    })

    latency_status = _status_for(snapshot["latency_p95_ms"], OBS_LATENCY_P95_WARN_MS, OBS_LATENCY_P95_FAIL_MS)
    alerts.append({
        "name": "http_latency_p95",
        "status": latency_status,
        "detail": f"p95={snapshot['latency_p95_ms']:.0f}ms",
    })

    try:
        queue_metrics = _ai_queue_depth_metrics()
        queue_depth = int(queue_metrics["queued_count"])
        failed_registry = int(queue_metrics["failed_registry_count"])
        alerts.append({
            "name": "ai_queue_depth",
            "status": "warn" if queue_depth >= AI_OPS_QUEUE_WARN_DEPTH else "ok",
            "detail": f"queued={queue_depth}",
        })
        alerts.append({
            "name": "ai_failed_registry",
            "status": "warn" if failed_registry >= AI_OPS_FAILED_REGISTRY_WARN else "ok",
            "detail": f"failed_registry={failed_registry}",
        })
    except Exception as error:
        alerts.append({
            "name": "ai_queue_metrics",
            "status": "fail",
            "detail": f"unavailable: {str(error)[:180]}",
        })

    recent_sent, recent_failed = _notification_window_counts(db)
    total_notification = recent_sent + recent_failed
    fail_rate = (recent_failed / total_notification) if total_notification > 0 else 0.0
    notif_status = "ok"
    if total_notification == 0:
        notif_status = "warn"
    elif fail_rate >= NOTIFICATION_FAILURE_WARN_RATE:
        notif_status = "warn"
    alerts.append({
        "name": "notification_delivery",
        "status": notif_status,
        "detail": (
            f"sent={recent_sent}, failed={recent_failed}, "
            f"failure_rate={fail_rate:.2%}"
        ),
    })

    if any(item["status"] == "fail" for item in alerts):
        overall_status = "fail"
    elif any(item["status"] == "warn" for item in alerts):
        overall_status = "warn"
    else:
        overall_status = "ok"

    return {
        "generated_at": now.isoformat(),
        "overall_status": overall_status,
        "alerts": alerts,
    }


@app.post("/ai/jobs/{job_id}/regenerate", response_model=schemas.AIJobCreateResponse)
def regenerate_ai_job(
    job_id: str,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    source = db.query(models.AIJob).filter(
        models.AIJob.id == job_id,
        models.AIJob.user_id == user.id,
    ).first()
    if not source:
        raise HTTPException(status_code=404, detail="AI job not found")

    _enforce_daily_quota(db, user.id)

    now = _utc_now()
    new_job = models.AIJob(
        id=str(uuid.uuid4()),
        user_id=user.id,
        job_type=source.job_type,
        status="queued",
        attempts=0,
        max_attempts=AI_JOB_MAX_ATTEMPTS,
        payload_json=source.payload_json,
        result_json=None,
        error_message=None,
        provider_used=None,
        model_used=None,
        prompt_version=AI_PROMPT_VERSION,
        created_at=now,
        updated_at=now,
        completed_at=None,
    )
    db.add(new_job)
    db.commit()

    try:
        _enqueue_ai_job(new_job.id, new_job.max_attempts)
    except Exception as error:
        new_job.error_message = f"Queue unavailable, processing inline: {str(error)[:420]}"
        new_job.updated_at = _utc_now()
        db.commit()
        try:
            _process_ai_job(new_job.id)
            db.refresh(new_job)
        except Exception as inline_error:
            new_job.status = "failed"
            new_job.error_message = f"Inline AI processing failed: {str(inline_error)[:420]}"
            new_job.completed_at = _utc_now()
            new_job.updated_at = _utc_now()
            db.commit()
            raise HTTPException(status_code=503, detail="AI queue unavailable")

    return {
        "job_id": new_job.id,
        "status": new_job.status,
        "queued_at": now.isoformat(),
    }

@app.get("/")
def read_root():
    return {"message": "Calm Clarity API is running"}
