from fastapi import FastAPI, Depends, HTTPException, status, Header, Request, Body, Response, UploadFile, File
from fastapi.responses import PlainTextResponse
from fastapi.middleware.cors import CORSMiddleware
import os
import secrets
import hashlib
import hmac
import base64
import struct
import smtplib
import json
import uuid
import time
import threading
import re
import html
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
from secret_manager import get_runtime_secret

load_dotenv()

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
CORS_ALLOW_ORIGINS = os.getenv("CORS_ALLOW_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000")
LOCAL_DEV_ORIGIN_REGEX = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
APP_ENV = os.getenv("APP_ENV", "development")
TRUST_PROXY_HEADERS = os.getenv("TRUST_PROXY_HEADERS", "true").lower() in {"1", "true", "yes"}
ENFORCE_HTTPS = os.getenv("ENFORCE_HTTPS", "true" if APP_ENV.lower() == "production" else "false").lower() in {"1", "true", "yes"}
HSTS_ENABLED = os.getenv("HSTS_ENABLED", "true").lower() in {"1", "true", "yes"}
HSTS_MAX_AGE_SECONDS = int(os.getenv("HSTS_MAX_AGE_SECONDS", "63072000"))
HSTS_INCLUDE_SUBDOMAINS = os.getenv("HSTS_INCLUDE_SUBDOMAINS", "true").lower() in {"1", "true", "yes"}
HSTS_PRELOAD = os.getenv("HSTS_PRELOAD", "false").lower() in {"1", "true", "yes"}
FRONTEND_BASE_URL = os.getenv("FRONTEND_BASE_URL", "http://localhost:3000")
FRONTEND_ROUTE_MODE = os.getenv("FRONTEND_ROUTE_MODE", "query").lower()
RESET_TOKEN_EXPIRE_MINUTES = int(os.getenv("RESET_TOKEN_EXPIRE_MINUTES", "30"))
EMAIL_VERIFICATION_EXPIRE_MINUTES = int(os.getenv("EMAIL_VERIFICATION_EXPIRE_MINUTES", "60"))
REQUIRE_EMAIL_VERIFICATION = os.getenv("REQUIRE_EMAIL_VERIFICATION", "false").lower() in {"1", "true", "yes"}
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
REFRESH_TOKEN_EXPIRE_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "14"))
OPENAI_API_KEY = get_runtime_secret("OPENAI_API_KEY", default="", enforce_managed_ref_in_production=True)
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
AI_PROVIDER = os.getenv("AI_PROVIDER", "auto").strip().lower()
GROQ_API_KEY = get_runtime_secret("GROQ_API_KEY", default="", enforce_managed_ref_in_production=True)
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.1-8b-instant")
GROQ_BASE_URL = os.getenv("GROQ_BASE_URL", "https://api.groq.com/openai/v1")
GEMINI_API_KEY = get_runtime_secret("GEMINI_API_KEY", default="", enforce_managed_ref_in_production=True)
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
ADMIN_API_KEY = get_runtime_secret("ADMIN_API_KEY", default="", enforce_managed_ref_in_production=True)
ADMIN_MFA_ISSUER = os.getenv("ADMIN_MFA_ISSUER", "CalmClarity")
ADMIN_MFA_WINDOW = int(os.getenv("ADMIN_MFA_WINDOW", "1"))
ADMIN_MFA_RECOVERY_CODES_COUNT = int(os.getenv("ADMIN_MFA_RECOVERY_CODES_COUNT", "8"))
ADMIN_MFA_RECOVERY_CODE_LENGTH = int(os.getenv("ADMIN_MFA_RECOVERY_CODE_LENGTH", "10"))
ADMIN_STEP_UP_TTL_SECONDS = int(os.getenv("ADMIN_STEP_UP_TTL_SECONDS", "300"))
ADMIN_ALLOWED_EMAILS = {
    email.strip().lower()
    for email in os.getenv("ADMIN_ALLOWED_EMAILS", "").split(",")
    if email.strip()
}
FCM_SERVER_KEY = get_runtime_secret("FCM_SERVER_KEY", default="", enforce_managed_ref_in_production=True)
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
SMTP_USERNAME = get_runtime_secret("SMTP_USERNAME", default="", enforce_managed_ref_in_production=True) or None
SMTP_PASSWORD = get_runtime_secret("SMTP_PASSWORD", default="", enforce_managed_ref_in_production=True) or None
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USERNAME or "")
SMTP_USE_TLS = os.getenv("SMTP_USE_TLS", "true").lower() in {"1", "true", "yes"}

PASSWORD_POLICY_MIN_LENGTH = int(os.getenv("PASSWORD_POLICY_MIN_LENGTH", "10"))
AUTH_USE_COOKIES = os.getenv("AUTH_USE_COOKIES", "false").lower() in {"1", "true", "yes"}
AUTH_COOKIE_NAME_ACCESS = os.getenv("AUTH_COOKIE_NAME_ACCESS", "cc_access_token")
AUTH_COOKIE_NAME_REFRESH = os.getenv("AUTH_COOKIE_NAME_REFRESH", "cc_refresh_token")
AUTH_COOKIE_DOMAIN = os.getenv("AUTH_COOKIE_DOMAIN", "").strip() or None
AUTH_COOKIE_PATH = os.getenv("AUTH_COOKIE_PATH", "/")
AUTH_COOKIE_SECURE = os.getenv("AUTH_COOKIE_SECURE", "true" if APP_ENV.lower() == "production" else "false").lower() in {"1", "true", "yes"}
AUTH_COOKIE_SAMESITE = os.getenv("AUTH_COOKIE_SAMESITE", "lax").strip().lower()

RATE_LIMIT_LOGIN_PER_IP = int(os.getenv("RATE_LIMIT_LOGIN_PER_IP", "30"))
RATE_LIMIT_LOGIN_PER_USER = int(os.getenv("RATE_LIMIT_LOGIN_PER_USER", "20"))
RATE_LIMIT_RESET_PER_IP = int(os.getenv("RATE_LIMIT_RESET_PER_IP", "20"))
RATE_LIMIT_RESET_PER_USER = int(os.getenv("RATE_LIMIT_RESET_PER_USER", "10"))
RATE_LIMIT_AI_PER_IP = int(os.getenv("RATE_LIMIT_AI_PER_IP", "120"))
RATE_LIMIT_AI_PER_USER = int(os.getenv("RATE_LIMIT_AI_PER_USER", "80"))
RATE_LIMIT_ADMIN_PER_IP = int(os.getenv("RATE_LIMIT_ADMIN_PER_IP", "120"))
RATE_LIMIT_ADMIN_PER_USER = int(os.getenv("RATE_LIMIT_ADMIN_PER_USER", "120"))
RATE_LIMIT_WINDOW_SECONDS = int(os.getenv("RATE_LIMIT_WINDOW_SECONDS", "60"))

AUTH_FAILURE_WINDOW_SECONDS = int(os.getenv("AUTH_FAILURE_WINDOW_SECONDS", "900"))
AUTH_LOCKOUT_SECONDS = int(os.getenv("AUTH_LOCKOUT_SECONDS", "600"))
AUTH_FAILURES_BEFORE_LOCKOUT = int(os.getenv("AUTH_FAILURES_BEFORE_LOCKOUT", "8"))
AUTH_FAILURES_BEFORE_CAPTCHA = int(os.getenv("AUTH_FAILURES_BEFORE_CAPTCHA", "5"))
ABUSE_CAPTCHA_ENABLED = os.getenv("ABUSE_CAPTCHA_ENABLED", "true").lower() in {"1", "true", "yes"}
ABUSE_CAPTCHA_PROVIDER = os.getenv("ABUSE_CAPTCHA_PROVIDER", "turnstile").strip().lower()
ABUSE_CAPTCHA_SECRET_KEY = get_runtime_secret(
    "ABUSE_CAPTCHA_SECRET_KEY",
    default="",
    enforce_managed_ref_in_production=True,
).strip()
ABUSE_CAPTCHA_VERIFY_URL = os.getenv("ABUSE_CAPTCHA_VERIFY_URL", "").strip()
ABUSE_CAPTCHA_EXPECTED_ACTION = os.getenv("ABUSE_CAPTCHA_EXPECTED_ACTION", "").strip()
ABUSE_CAPTCHA_MIN_SCORE = float(os.getenv("ABUSE_CAPTCHA_MIN_SCORE", "0.5"))
ABUSE_CAPTCHA_TIMEOUT_SECONDS = int(os.getenv("ABUSE_CAPTCHA_TIMEOUT_SECONDS", "8"))

MAX_REQUEST_BODY_BYTES = int(os.getenv("MAX_REQUEST_BODY_BYTES", "1048576"))
MAX_JSON_BODY_BYTES = int(os.getenv("MAX_JSON_BODY_BYTES", "524288"))
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", "5242880"))
ALLOWED_UPLOAD_MIME_TYPES = {
    value.strip().lower()
    for value in os.getenv("ALLOWED_UPLOAD_MIME_TYPES", "image/jpeg,image/png,image/webp").split(",")
    if value.strip()
}
CSRF_PROTECTION_ENABLED = os.getenv("CSRF_PROTECTION_ENABLED", "true").lower() in {"1", "true", "yes"}
CSRF_COOKIE_NAME = os.getenv("CSRF_COOKIE_NAME", "cc_csrf_token").strip() or "cc_csrf_token"
CSRF_HEADER_NAME = os.getenv("CSRF_HEADER_NAME", "X-CSRF-Token").strip() or "X-CSRF-Token"

_obs_lock = threading.Lock()
_obs_request_total = 0
_obs_error_total = 0
_obs_status_counts = defaultdict(int)
_obs_path_counts = defaultdict(int)
_obs_samples: list[tuple[float, float, int]] = []
_semantic_model_lock = threading.Lock()
_semantic_model = None
_rate_limit_lock = threading.Lock()
_rate_limit_events: dict[str, list[float]] = defaultdict(list)
_auth_failure_events: dict[str, list[float]] = defaultdict(list)
_auth_lockouts: dict[str, float] = {}


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


def _ensure_user_security_columns() -> None:
    inspector = inspect(engine)
    try:
        columns = [column["name"] for column in inspector.get_columns("users")]
    except Exception:
        return

    with engine.begin() as connection:
        if "email_verified" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN email_verified INTEGER DEFAULT 0"))
            connection.execute(text("UPDATE users SET email_verified = 0 WHERE email_verified IS NULL"))
        if "token_version" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN token_version INTEGER DEFAULT 0"))
            connection.execute(text("UPDATE users SET token_version = 0 WHERE token_version IS NULL"))
        if "admin_mfa_enabled" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN admin_mfa_enabled INTEGER DEFAULT 0"))
            connection.execute(text("UPDATE users SET admin_mfa_enabled = 0 WHERE admin_mfa_enabled IS NULL"))
        if "admin_mfa_secret" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN admin_mfa_secret VARCHAR"))
        if "role" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN role VARCHAR DEFAULT 'user'"))
            connection.execute(text("UPDATE users SET role = 'user' WHERE role IS NULL OR TRIM(role) = ''"))


def _ensure_refresh_token_columns() -> None:
    inspector = inspect(engine)
    try:
        columns = [column["name"] for column in inspector.get_columns("refresh_tokens")]
    except Exception:
        return

    with engine.begin() as connection:
        if "last_used_at" not in columns:
            connection.execute(text("ALTER TABLE refresh_tokens ADD COLUMN last_used_at DATETIME"))
        if "client_ip" not in columns:
            connection.execute(text("ALTER TABLE refresh_tokens ADD COLUMN client_ip VARCHAR"))
        if "user_agent" not in columns:
            connection.execute(text("ALTER TABLE refresh_tokens ADD COLUMN user_agent VARCHAR"))
        if "device_label" not in columns:
            connection.execute(text("ALTER TABLE refresh_tokens ADD COLUMN device_label VARCHAR"))


def _is_admin_email(email: str | None) -> bool:
    normalized = (email or "").strip().lower()
    return bool(normalized) and normalized in ADMIN_ALLOWED_EMAILS


def _sync_user_role(
    user: models.User,
    *,
    db: Session | None = None,
    request: Request | None = None,
    actor_user: models.User | None = None,
    reason: str = "allowlist_sync",
) -> None:
    previous_role = (user.role or "user").strip().lower()
    next_role = "admin" if _is_admin_email(user.email) else "user"
    user.role = next_role
    if db is not None and previous_role != next_role:
        _append_security_audit_log(
            db,
            event_type="role_changed",
            severity="warn",
            actor_user=actor_user,
            actor_email=actor_user.email if actor_user is not None else user.email,
            target_user=user,
            request=request,
            metadata={
                "previous_role": previous_role,
                "new_role": next_role,
                "reason": reason,
            },
        )


def _is_admin_user(user: models.User) -> bool:
    return (user.role or "").strip().lower() == "admin"


def _assert_self_or_admin(current_user: models.User, target_user_id: int) -> None:
    if current_user.id == target_user_id:
        return
    if _is_admin_user(current_user):
        return
    raise HTTPException(status_code=403, detail="Forbidden")


def _client_ip(request: Request) -> str:
    if TRUST_PROXY_HEADERS:
        forwarded_for = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
        if forwarded_for:
            return forwarded_for
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def _append_event_and_count(store: dict[str, list[float]], key: str, window_seconds: int, now_epoch: float) -> int:
    events = store.setdefault(key, [])
    cutoff = now_epoch - max(1, window_seconds)
    events[:] = [stamp for stamp in events if stamp >= cutoff]
    events.append(now_epoch)
    return len(events)


def _enforce_rate_limit(scope: str, identifier: str, limit: int, window_seconds: int) -> None:
    if limit <= 0:
        return
    key = f"{scope}:{identifier.strip().lower()}"
    now_epoch = time.time()
    with _rate_limit_lock:
        count = _append_event_and_count(_rate_limit_events, key, window_seconds, now_epoch)
    if count > limit:
        raise HTTPException(status_code=429, detail="Rate limit exceeded")


def _auth_lockout_key(email: str, ip_address: str) -> str:
    return f"{(email or '').strip().lower()}|{(ip_address or 'unknown').strip().lower()}"


def _enforce_auth_lockout(email: str, ip_address: str) -> None:
    key = _auth_lockout_key(email, ip_address)
    now_epoch = time.time()
    with _rate_limit_lock:
        locked_until = _auth_lockouts.get(key)
        if locked_until and locked_until > now_epoch:
            raise HTTPException(status_code=429, detail="Too many failed attempts. Try again later.")
        if locked_until and locked_until <= now_epoch:
            _auth_lockouts.pop(key, None)


def _record_auth_failure(email: str, ip_address: str) -> int:
    key = _auth_lockout_key(email, ip_address)
    now_epoch = time.time()
    with _rate_limit_lock:
        count = _append_event_and_count(_auth_failure_events, key, AUTH_FAILURE_WINDOW_SECONDS, now_epoch)
        if count >= max(1, AUTH_FAILURES_BEFORE_LOCKOUT):
            _auth_lockouts[key] = now_epoch + max(30, AUTH_LOCKOUT_SECONDS)
    return count


def _clear_auth_failures(email: str, ip_address: str) -> None:
    key = _auth_lockout_key(email, ip_address)
    with _rate_limit_lock:
        _auth_failure_events.pop(key, None)
        _auth_lockouts.pop(key, None)


def _is_captcha_required(email: str, ip_address: str) -> bool:
    key = _auth_lockout_key(email, ip_address)
    now_epoch = time.time()
    with _rate_limit_lock:
        events = _auth_failure_events.get(key, [])
        cutoff = now_epoch - max(1, AUTH_FAILURE_WINDOW_SECONDS)
        count = len([stamp for stamp in events if stamp >= cutoff])
    return count >= max(1, AUTH_FAILURES_BEFORE_CAPTCHA)


def _verify_abuse_captcha(request: Request) -> bool:
    token = (request.headers.get("X-Captcha-Token") or "").strip()
    if not token:
        return False

    if not ABUSE_CAPTCHA_SECRET_KEY:
        return APP_ENV.lower() != "production"

    provider = ABUSE_CAPTCHA_PROVIDER or "turnstile"
    verify_url = ABUSE_CAPTCHA_VERIFY_URL
    if not verify_url:
        if provider == "recaptcha":
            verify_url = "https://www.google.com/recaptcha/api/siteverify"
        else:
            verify_url = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

    form_payload = {
        "secret": ABUSE_CAPTCHA_SECRET_KEY,
        "response": token,
        "remoteip": _client_ip(request),
    }

    try:
        response = requests.post(
            verify_url,
            data=form_payload,
            timeout=max(2, ABUSE_CAPTCHA_TIMEOUT_SECONDS),
        )
    except Exception:
        return False

    if response.status_code >= 400:
        return False

    try:
        result = response.json()
    except Exception:
        return False

    if result.get("success") is not True:
        return False

    expected_action = (ABUSE_CAPTCHA_EXPECTED_ACTION or "").strip()
    if provider == "recaptcha":
        score = float(result.get("score", 0.0) or 0.0)
        if score < max(0.0, min(1.0, ABUSE_CAPTCHA_MIN_SCORE)):
            return False
        if expected_action and (result.get("action") or "").strip() != expected_action:
            return False
    else:
        if expected_action and (result.get("action") or "").strip() != expected_action:
            return False

    return True


def _enforce_login_abuse_controls(request: Request, email: str) -> None:
    ip_address = _client_ip(request)
    _enforce_rate_limit("login_ip", ip_address, RATE_LIMIT_LOGIN_PER_IP, RATE_LIMIT_WINDOW_SECONDS)
    _enforce_rate_limit("login_user", email, RATE_LIMIT_LOGIN_PER_USER, RATE_LIMIT_WINDOW_SECONDS)
    _enforce_auth_lockout(email, ip_address)
    if ABUSE_CAPTCHA_ENABLED and _is_captcha_required(email, ip_address):
        if not _verify_abuse_captcha(request):
            raise HTTPException(status_code=429, detail="Captcha required")


def _enforce_reset_abuse_controls(request: Request, email: str) -> None:
    ip_address = _client_ip(request)
    _enforce_rate_limit("reset_ip", ip_address, RATE_LIMIT_RESET_PER_IP, RATE_LIMIT_WINDOW_SECONDS)
    if email.strip():
        _enforce_rate_limit("reset_user", email, RATE_LIMIT_RESET_PER_USER, RATE_LIMIT_WINDOW_SECONDS)


def _enforce_ai_abuse_controls(request: Request, user_id: int) -> None:
    ip_address = _client_ip(request)
    _enforce_rate_limit("ai_ip", ip_address, RATE_LIMIT_AI_PER_IP, RATE_LIMIT_WINDOW_SECONDS)
    _enforce_rate_limit("ai_user", str(user_id), RATE_LIMIT_AI_PER_USER, RATE_LIMIT_WINDOW_SECONDS)


def _enforce_admin_abuse_controls(request: Request, user_id: int) -> None:
    ip_address = _client_ip(request)
    _enforce_rate_limit("admin_ip", ip_address, RATE_LIMIT_ADMIN_PER_IP, RATE_LIMIT_WINDOW_SECONDS)
    _enforce_rate_limit("admin_user", str(user_id), RATE_LIMIT_ADMIN_PER_USER, RATE_LIMIT_WINDOW_SECONDS)


def _audit_request_context(request: Request | None) -> tuple[str | None, str | None]:
    if request is None:
        return None, None
    ip_address = _client_ip(request)
    user_agent = (request.headers.get("user-agent") or "").strip()[:512] or None
    return ip_address, user_agent


def _append_security_audit_log(
    db: Session,
    *,
    event_type: str,
    severity: str = "info",
    actor_user: models.User | None = None,
    actor_email: str | None = None,
    target_user: models.User | None = None,
    target_user_id: int | None = None,
    request: Request | None = None,
    metadata: dict | None = None,
) -> None:
    now = _utc_now()
    ip_address, user_agent = _audit_request_context(request)
    previous = db.query(models.SecurityAuditLog).order_by(models.SecurityAuditLog.id.desc()).first()
    previous_hash = previous.record_hash if previous else ""

    safe_metadata = metadata or {}
    payload = {
        "event_type": event_type,
        "severity": severity,
        "actor_user_id": int(actor_user.id) if actor_user is not None else None,
        "actor_email": (actor_email or (actor_user.email if actor_user is not None else None)),
        "target_user_id": (
            int(target_user.id)
            if target_user is not None
            else (int(target_user_id) if target_user_id is not None else None)
        ),
        "ip_address": ip_address,
        "user_agent": user_agent,
        "metadata": safe_metadata,
        "occurred_at": now.isoformat(),
    }
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    record_hash = hashlib.sha256(f"{previous_hash}|{canonical}".encode("utf-8")).hexdigest()

    db.add(
        models.SecurityAuditLog(
            event_id=str(uuid.uuid4()),
            occurred_at=now,
            event_type=event_type,
            severity=severity,
            actor_user_id=int(actor_user.id) if actor_user is not None else None,
            actor_email=(actor_email or (actor_user.email if actor_user is not None else None)),
            target_user_id=(
                int(target_user.id)
                if target_user is not None
                else (int(target_user_id) if target_user_id is not None else None)
            ),
            ip_address=ip_address,
            user_agent=user_agent,
            metadata_json=json.dumps(safe_metadata, sort_keys=True),
            previous_hash=previous_hash or None,
            record_hash=record_hash,
        )
    )


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


def _extract_bearer_token(
    request: Request,
    authorization: str | None = Header(default=None),
) -> str:
    if authorization and authorization.startswith("Bearer "):
        return authorization.split(" ", 1)[1]

    if AUTH_USE_COOKIES:
        cookie_token = (request.cookies.get(AUTH_COOKIE_NAME_ACCESS) or "").strip()
        if cookie_token:
            return cookie_token

    raise HTTPException(status_code=401, detail="Invalid authorization header")


def _get_current_user(
    request: Request,
    token: str = Depends(_extract_bearer_token),
    db: Session = Depends(get_db),
) -> models.User:
    try:
        payload = auth.decode_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    email = payload.get("sub")
    token_type = payload.get("token_type")
    token_jti = payload.get("jti")
    token_version = int(payload.get("tv", 0))
    if not email:
        raise HTTPException(status_code=401, detail="Invalid token payload")
    if token_type != "access":
        raise HTTPException(status_code=401, detail="Invalid token type")
    if not token_jti:
        raise HTTPException(status_code=401, detail="Missing token identifier")

    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")

    previous_role = (user.role or "user").strip().lower()
    _sync_user_role(user, db=db, request=request, actor_user=user, reason="request_auth")
    if (user.role or "").strip().lower() != previous_role:
        db.commit()
        db.refresh(user)

    if int(user.is_active or 0) != 1:
        raise HTTPException(status_code=403, detail="Account is suspended")
    if int(user.token_version or 0) != token_version:
        raise HTTPException(status_code=401, detail="Session has been revoked")

    blocked = db.query(models.AccessTokenBlocklist).filter(
        models.AccessTokenBlocklist.jti == token_jti,
        models.AccessTokenBlocklist.expires_at > _utc_now(),
    ).first()
    if blocked:
        raise HTTPException(status_code=401, detail="Token has been revoked")
    return user


def _require_admin(
    request: Request,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
    admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
    admin_totp: str | None = Header(default=None, alias="X-Admin-TOTP"),
    admin_recovery_code: str | None = Header(default=None, alias="X-Admin-Recovery-Code"),
) -> models.User:
    _enforce_admin_abuse_controls(request, user.id)

    if not _is_admin_user(user):
        raise HTTPException(status_code=403, detail="Admin role required")

    if ADMIN_API_KEY.strip() and (admin_key or "").strip() != ADMIN_API_KEY.strip():
        raise HTTPException(status_code=403, detail="Invalid admin key")

    if ADMIN_ALLOWED_EMAILS and (user.email or "").strip().lower() not in ADMIN_ALLOWED_EMAILS:
        raise HTTPException(status_code=403, detail="Admin access denied")

    skip_inline_mfa = request.url.path.rstrip("/") == "/admin/re-auth"
    if int(user.admin_mfa_enabled or 0) == 1 and not skip_inline_mfa:
        secret = (user.admin_mfa_secret or "").strip()
        if not secret:
            raise HTTPException(status_code=403, detail="Admin MFA is not configured")
        has_valid_totp = _verify_totp(secret, admin_totp or "", window=ADMIN_MFA_WINDOW)
        used_recovery = False
        if not has_valid_totp:
            used_recovery = _redeem_admin_recovery_code(db, user, admin_recovery_code or "")
            if not used_recovery:
                raise HTTPException(status_code=403, detail="Invalid admin MFA code")

        if used_recovery:
            _append_security_audit_log(
                db,
                event_type="admin_mfa_recovery_used",
                severity="critical",
                actor_user=user,
                target_user=user,
                request=request,
            )
            db.commit()

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


def _request_scheme(request: Request) -> str:
    scheme = (request.url.scheme or "").strip().lower()
    if TRUST_PROXY_HEADERS:
        forwarded = (request.headers.get("x-forwarded-proto") or "").split(",")[0].strip().lower()
        if forwarded:
            scheme = forwarded
    return scheme or "http"


def _build_hsts_value() -> str:
    directives = [f"max-age={max(300, HSTS_MAX_AGE_SECONDS)}"]
    if HSTS_INCLUDE_SUBDOMAINS:
        directives.append("includeSubDomains")
    if HSTS_PRELOAD:
        directives.append("preload")
    return "; ".join(directives)


def _resolve_cors_settings() -> tuple[list[str], str | None, bool]:
    origins, wildcard = _parse_cors_origins(CORS_ALLOW_ORIGINS)
    env = APP_ENV.lower().strip()

    if env == "production":
        if wildcard:
            raise RuntimeError("CORS wildcard is not allowed in production. Set explicit trusted origins.")
        for origin in origins:
            if not origin.lower().startswith("https://"):
                raise RuntimeError(f"Production CORS origin must use https: {origin}")
        return origins, None, True

    if wildcard:
        return [], LOCAL_DEV_ORIGIN_REGEX, True
    return origins, None, True


def _normalize_samesite(value: str) -> str:
    mapping = {
        "strict": "strict",
        "lax": "lax",
        "none": "none",
    }
    resolved = mapping.get((value or "").strip().lower(), "lax")
    if resolved == "none" and not AUTH_COOKIE_SECURE:
        return "lax"
    return resolved


def _set_auth_cookies(response: Response, access_token: str, refresh_token: str) -> None:
    if not AUTH_USE_COOKIES:
        return

    same_site = _normalize_samesite(AUTH_COOKIE_SAMESITE)
    response.set_cookie(
        key=AUTH_COOKIE_NAME_ACCESS,
        value=access_token,
        httponly=True,
        secure=AUTH_COOKIE_SECURE,
        samesite=same_site,
        domain=AUTH_COOKIE_DOMAIN,
        path=AUTH_COOKIE_PATH,
        max_age=max(60, ACCESS_TOKEN_EXPIRE_MINUTES * 60),
    )
    response.set_cookie(
        key=AUTH_COOKIE_NAME_REFRESH,
        value=refresh_token,
        httponly=True,
        secure=AUTH_COOKIE_SECURE,
        samesite=same_site,
        domain=AUTH_COOKIE_DOMAIN,
        path=AUTH_COOKIE_PATH,
        max_age=max(3600, REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60),
    )

    if CSRF_PROTECTION_ENABLED:
        response.set_cookie(
            key=CSRF_COOKIE_NAME,
            value=secrets.token_urlsafe(24),
            httponly=False,
            secure=AUTH_COOKIE_SECURE,
            samesite=same_site,
            domain=AUTH_COOKIE_DOMAIN,
            path=AUTH_COOKIE_PATH,
            max_age=max(3600, REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60),
        )


def _clear_auth_cookies(response: Response) -> None:
    if not AUTH_USE_COOKIES:
        return

    same_site = _normalize_samesite(AUTH_COOKIE_SAMESITE)
    response.delete_cookie(
        key=AUTH_COOKIE_NAME_ACCESS,
        domain=AUTH_COOKIE_DOMAIN,
        path=AUTH_COOKIE_PATH,
        secure=AUTH_COOKIE_SECURE,
        httponly=True,
        samesite=same_site,
    )
    response.delete_cookie(
        key=AUTH_COOKIE_NAME_REFRESH,
        domain=AUTH_COOKIE_DOMAIN,
        path=AUTH_COOKIE_PATH,
        secure=AUTH_COOKIE_SECURE,
        httponly=True,
        samesite=same_site,
    )
    if CSRF_PROTECTION_ENABLED:
        response.delete_cookie(
            key=CSRF_COOKIE_NAME,
            domain=AUTH_COOKIE_DOMAIN,
            path=AUTH_COOKIE_PATH,
            secure=AUTH_COOKIE_SECURE,
            httponly=False,
            samesite=same_site,
        )


def _sanitize_rich_text(value: str | None, *, max_len: int = 12000) -> str:
    raw = (value or "")[:max(1, max_len)]
    cleaned = "".join(ch for ch in raw if ch >= " " or ch in {"\n", "\t", "\r"})
    return html.escape(cleaned, quote=False)


def _scan_upload_content(content: bytes) -> str:
    lowered = content.lower()
    signatures = [b"<script", b"<?php", b"<iframe", b"javascript:", b"vbscript:", b"onerror="]
    if any(sig in lowered for sig in signatures):
        return "malicious_markup_detected"
    if content.startswith(b"MZ"):
        return "binary_executable_detected"
    return "clean"


def _validate_upload_magic(content: bytes, content_type: str) -> bool:
    ctype = (content_type or "").strip().lower()
    if ctype == "image/jpeg":
        return content.startswith(b"\xff\xd8\xff")
    if ctype == "image/png":
        return content.startswith(b"\x89PNG\r\n\x1a\n")
    if ctype == "image/webp":
        return content.startswith(b"RIFF") and b"WEBP" in content[:20]
    return False


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


def _validate_password_policy(password: str) -> None:
    value = (password or "").strip()
    if len(value) < PASSWORD_POLICY_MIN_LENGTH:
        raise HTTPException(status_code=400, detail=f"Password must be at least {PASSWORD_POLICY_MIN_LENGTH} characters")
    if not re.search(r"[a-z]", value):
        raise HTTPException(status_code=400, detail="Password must include at least one lowercase letter")
    if not re.search(r"\d", value):
        raise HTTPException(status_code=400, detail="Password must include at least one number")
    if not re.search(r"[^A-Za-z0-9]", value):
        raise HTTPException(status_code=400, detail="Password must include at least one special character")


def _build_email_verification_link(token: str) -> str:
    base = FRONTEND_BASE_URL.rstrip("/")
    if FRONTEND_ROUTE_MODE == "query":
        return f"{base}/?verify_email_token={token}"
    if FRONTEND_ROUTE_MODE == "path":
        return f"{base}/verify-email?token={token}"
    return f"{base}/#/verify-email?token={token}"


def _send_email_verification(recipient_email: str, verification_token: str) -> bool:
    if not SMTP_HOST or not SMTP_FROM:
        return False

    verification_link = _build_email_verification_link(verification_token)
    msg = EmailMessage()
    msg["Subject"] = "Verify your Calm Clarity email"
    msg["From"] = SMTP_FROM
    msg["To"] = recipient_email
    msg.set_content(
        "Welcome to Calm Clarity!\n\n"
        f"Verify your email to secure your account (expires in {EMAIL_VERIFICATION_EXPIRE_MINUTES} minutes):\n"
        f"{verification_link}\n\n"
        "If this wasn’t you, you can ignore this message."
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


def _hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _session_device_label(request: Request | None) -> str | None:
    if request is None:
        return None
    explicit = (request.headers.get("x-device-name") or "").strip()
    if explicit:
        return explicit[:120]
    user_agent = (request.headers.get("user-agent") or "").strip()
    if not user_agent:
        return None
    return user_agent[:120]


def _issue_token_pair(
    db: Session,
    user: models.User,
    family_id: str | None = None,
    *,
    request: Request | None = None,
) -> tuple[str, str]:
    now = _utc_now()
    access_jti = str(uuid.uuid4())
    refresh_jti = str(uuid.uuid4())
    active_family_id = family_id or str(uuid.uuid4())

    access_token = auth.create_access_token(
        data={
            "sub": user.email,
            "jti": access_jti,
            "tv": int(user.token_version or 0),
        },
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = auth.create_refresh_token(
        data={
            "sub": user.email,
            "jti": refresh_jti,
            "tv": int(user.token_version or 0),
            "fid": active_family_id,
        },
        expires_delta=timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
    )

    db.add(
        models.RefreshToken(
            user_id=user.id,
            jti=refresh_jti,
            family_id=active_family_id,
            token_hash=_hash_refresh_token(refresh_token),
            issued_at=now,
            expires_at=now + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
            last_used_at=now,
            client_ip=_client_ip(request) if request is not None else None,
            user_agent=((request.headers.get("user-agent") or "").strip()[:512] if request is not None else None),
            device_label=_session_device_label(request),
            revoked_at=None,
            replaced_by_jti=None,
            revoked_reason=None,
        )
    )
    return access_token, refresh_token


def _list_user_sessions_payload(
    db: Session,
    *,
    user_id: int,
    current_refresh_token_hash: str | None = None,
) -> dict:
    sessions = db.query(models.RefreshToken).filter(
        models.RefreshToken.user_id == int(user_id),
    ).order_by(models.RefreshToken.issued_at.desc()).limit(100).all()

    session_items = []
    active_count = 0
    for session in sessions:
        is_active = session.revoked_at is None and session.expires_at > _utc_now()
        if is_active:
            active_count += 1
        session_items.append(
            {
                "session_id": int(session.id),
                "issued_at": session.issued_at.isoformat(),
                "expires_at": session.expires_at.isoformat(),
                "last_used_at": session.last_used_at.isoformat() if session.last_used_at else None,
                "revoked_at": session.revoked_at.isoformat() if session.revoked_at else None,
                "revoked_reason": session.revoked_reason,
                "client_ip": session.client_ip,
                "user_agent": session.user_agent,
                "device_label": session.device_label,
                "current": bool(current_refresh_token_hash and session.token_hash == current_refresh_token_hash),
            }
        )

    devices = db.query(models.NotificationDevice).filter(
        models.NotificationDevice.user_id == int(user_id),
    ).order_by(models.NotificationDevice.last_seen_at.desc()).limit(100).all()
    device_items = [
        {
            "id": int(device.id),
            "device_id": device.device_id,
            "platform": device.platform,
            "push_enabled": bool(device.push_enabled),
            "app_version": device.app_version,
            "last_seen_at": device.last_seen_at.isoformat() if device.last_seen_at else None,
        }
        for device in devices
    ]

    return {
        "generated_at": _utc_now().isoformat(),
        "total_sessions": int(len(session_items)),
        "active_sessions": int(active_count),
        "sessions": session_items,
        "devices": device_items,
    }


def _revoke_all_user_sessions(
    db: Session,
    *,
    user: models.User,
    reason: str,
    actor_user: models.User | None = None,
    request: Request | None = None,
    bump_token_version: bool = True,
) -> int:
    now = _utc_now()
    active_count = db.query(models.RefreshToken).filter(
        models.RefreshToken.user_id == user.id,
        models.RefreshToken.revoked_at.is_(None),
    ).count()
    db.query(models.RefreshToken).filter(
        models.RefreshToken.user_id == user.id,
        models.RefreshToken.revoked_at.is_(None),
    ).update(
        {
            "revoked_at": now,
            "revoked_reason": reason,
        },
        synchronize_session=False,
    )
    if bump_token_version:
        user.token_version = int(user.token_version or 0) + 1

    _append_security_audit_log(
        db,
        event_type="user_sessions_revoked",
        severity="critical" if bump_token_version else "warn",
        actor_user=actor_user or user,
        target_user=user,
        request=request,
        metadata={
            "reason": reason,
            "active_sessions_revoked": int(active_count),
            "token_version_bumped": bool(bump_token_version),
        },
    )
    return int(active_count)


def _revoke_access_token(
    db: Session,
    token: str,
    reason: str = "logout",
    actor_user: models.User | None = None,
    request: Request | None = None,
) -> None:
    try:
        payload = auth.decode_token(token)
    except ValueError:
        return

    if payload.get("token_type") != "access":
        return

    email = payload.get("sub")
    jti = payload.get("jti")
    exp_ts = payload.get("exp")
    if not email or not jti or not exp_ts:
        return

    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        return

    expires_at = datetime.utcfromtimestamp(int(exp_ts))
    existing = db.query(models.AccessTokenBlocklist).filter(models.AccessTokenBlocklist.jti == jti).first()
    if existing:
        return

    db.add(
        models.AccessTokenBlocklist(
            user_id=user.id,
            jti=jti,
            expires_at=expires_at,
            revoked_at=_utc_now(),
            revoked_reason=reason,
        )
    )
    _append_security_audit_log(
        db,
        event_type="access_token_revoked",
        severity="warn",
        actor_user=actor_user,
        target_user=user,
        request=request,
        metadata={"reason": reason, "jti": jti},
    )


def _revoke_refresh_token(
    db: Session,
    refresh_token: str,
    reason: str = "logout",
    actor_user: models.User | None = None,
    request: Request | None = None,
) -> models.RefreshToken | None:
    token_hash = _hash_refresh_token(refresh_token)
    record = db.query(models.RefreshToken).filter(models.RefreshToken.token_hash == token_hash).first()
    if not record:
        return None
    if record.revoked_at is None:
        record.revoked_at = _utc_now()
        record.revoked_reason = reason
        _append_security_audit_log(
            db,
            event_type="refresh_token_revoked",
            severity="warn",
            actor_user=actor_user,
            target_user_id=int(record.user_id),
            request=request,
            metadata={"reason": reason, "jti": record.jti, "family_id": record.family_id},
        )
    return record


def _revoke_refresh_family(
    db: Session,
    family_id: str,
    reason: str,
    actor_user: models.User | None = None,
    target_user: models.User | None = None,
    request: Request | None = None,
) -> None:
    now = _utc_now()
    db.query(models.RefreshToken).filter(
        models.RefreshToken.family_id == family_id,
        models.RefreshToken.revoked_at.is_(None),
    ).update(
        {
            "revoked_at": now,
            "revoked_reason": reason,
        },
        synchronize_session=False,
    )
    _append_security_audit_log(
        db,
        event_type="refresh_family_revoked",
        severity="critical",
        actor_user=actor_user,
        target_user=target_user,
        request=request,
        metadata={"reason": reason, "family_id": family_id},
    )


def _generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("utf-8").replace("=", "")


def _totp_code(secret: str, counter: int) -> str:
    normalized = secret.strip().upper()
    padding = "=" * ((8 - (len(normalized) % 8)) % 8)
    key = base64.b32decode(normalized + padding, casefold=True)
    msg = struct.pack(">Q", counter)
    digest = hmac.new(key, msg, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    binary = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return f"{binary % 1000000:06d}"


def _verify_totp(secret: str, code: str, window: int = 1) -> bool:
    clean_code = (code or "").strip()
    if not re.fullmatch(r"\d{6}", clean_code):
        return False
    now_counter = int(time.time() // 30)
    for offset in range(-max(0, window), max(0, window) + 1):
        if secrets.compare_digest(_totp_code(secret, now_counter + offset), clean_code):
            return True
    return False


def _normalize_recovery_code(code: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", (code or "").strip()).upper()


def _hash_recovery_code(user_id: int, code: str) -> str:
    normalized = _normalize_recovery_code(code)
    return hashlib.sha256(f"{int(user_id)}:{normalized}".encode("utf-8")).hexdigest()


def _hash_admin_step_up_token(token: str) -> str:
    return hashlib.sha256((token or "").encode("utf-8")).hexdigest()


def _generate_recovery_code(*, length: int) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    safe_length = max(8, min(length, 20))
    left = max(4, safe_length // 2)
    right = safe_length - left
    first = "".join(secrets.choice(alphabet) for _ in range(left))
    second = "".join(secrets.choice(alphabet) for _ in range(right))
    return f"{first}-{second}"


def _generate_admin_recovery_codes(db: Session, user: models.User) -> list[str]:
    now = _utc_now()
    db.query(models.AdminMfaRecoveryCode).filter(
        models.AdminMfaRecoveryCode.user_id == user.id,
        models.AdminMfaRecoveryCode.used_at.is_(None),
        models.AdminMfaRecoveryCode.replaced_at.is_(None),
    ).update(
        {"replaced_at": now},
        synchronize_session=False,
    )

    generated_codes: list[str] = []
    count = max(4, min(20, ADMIN_MFA_RECOVERY_CODES_COUNT))
    while len(generated_codes) < count:
        code = _generate_recovery_code(length=ADMIN_MFA_RECOVERY_CODE_LENGTH)
        if code in generated_codes:
            continue
        generated_codes.append(code)
        db.add(
            models.AdminMfaRecoveryCode(
                user_id=user.id,
                code_hash=_hash_recovery_code(user.id, code),
                created_at=now,
                used_at=None,
                replaced_at=None,
            )
        )
    return generated_codes


def _redeem_admin_recovery_code(db: Session, user: models.User, code: str) -> bool:
    normalized = _normalize_recovery_code(code)
    if not normalized:
        return False

    record = db.query(models.AdminMfaRecoveryCode).filter(
        models.AdminMfaRecoveryCode.user_id == user.id,
        models.AdminMfaRecoveryCode.code_hash == _hash_recovery_code(user.id, normalized),
        models.AdminMfaRecoveryCode.used_at.is_(None),
        models.AdminMfaRecoveryCode.replaced_at.is_(None),
    ).first()
    if record is None:
        return False

    record.used_at = _utc_now()
    return True


def _consume_admin_step_up_token(
    db: Session,
    user: models.User,
    token: str,
    *,
    action: str,
    request: Request | None = None,
) -> None:
    clean = (token or "").strip()
    if not clean:
        raise HTTPException(status_code=403, detail="Admin re-auth required")

    now = _utc_now()
    token_hash = _hash_admin_step_up_token(clean)
    session = db.query(models.AdminStepUpSession).filter(
        models.AdminStepUpSession.user_id == user.id,
        models.AdminStepUpSession.token_hash == token_hash,
        models.AdminStepUpSession.used_at.is_(None),
        models.AdminStepUpSession.expires_at > now,
    ).first()
    if session is None:
        raise HTTPException(status_code=403, detail="Admin re-auth required")

    session.used_at = now
    session.used_for_action = action[:120]
    _append_security_audit_log(
        db,
        event_type="admin_step_up_consumed",
        severity="warn",
        actor_user=user,
        target_user=user,
        request=request,
        metadata={"action": action},
    )


def _require_sensitive_admin_reauth(
    request: Request,
    user: models.User,
    db: Session,
    *,
    action: str,
) -> None:
    token = (request.headers.get("X-Admin-Reauth") or "").strip()
    _consume_admin_step_up_token(db, user, token, action=action, request=request)


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
        "summary": _sanitize_rich_text((payload.get("summary") or "Untitled").strip() or "Untitled", max_len=240),
        "description": _sanitize_rich_text(payload.get("description") or "", max_len=5000),
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
_ensure_user_security_columns()
_ensure_refresh_token_columns()

app = FastAPI(title="Calm Clarity Backend")


@app.middleware("http")
async def observability_http_middleware(request: Request, call_next):
    started = time.perf_counter()
    status_code = 500
    try:
        scheme = _request_scheme(request)
        if ENFORCE_HTTPS and scheme != "https":
            status_code = 400
            return PlainTextResponse("HTTPS is required", status_code=400)

        content_length_header = (request.headers.get("content-length") or "").strip()
        if content_length_header.isdigit():
            content_length = int(content_length_header)
            if content_length > max(1024, MAX_REQUEST_BODY_BYTES):
                status_code = 413
                return PlainTextResponse("Request payload too large", status_code=413)
            content_type = (request.headers.get("content-type") or "").lower()
            if "application/json" in content_type and content_length > max(1024, MAX_JSON_BODY_BYTES):
                status_code = 413
                return PlainTextResponse("JSON payload too large", status_code=413)

        if AUTH_USE_COOKIES and CSRF_PROTECTION_ENABLED and request.method in {"POST", "PUT", "PATCH", "DELETE"}:
            has_cookie_session = bool((request.cookies.get(AUTH_COOKIE_NAME_ACCESS) or "").strip())
            if has_cookie_session:
                csrf_cookie = (request.cookies.get(CSRF_COOKIE_NAME) or "").strip()
                csrf_header = (request.headers.get(CSRF_HEADER_NAME) or "").strip()
                if not csrf_cookie or not csrf_header or not secrets.compare_digest(csrf_cookie, csrf_header):
                    status_code = 403
                    return PlainTextResponse("CSRF validation failed", status_code=403)

        response = await call_next(request)
        status_code = int(response.status_code)

        if HSTS_ENABLED and scheme == "https":
            response.headers["Strict-Transport-Security"] = _build_hsts_value()
        return response
    except Exception:
        status_code = 500
        raise
    finally:
        duration_ms = (time.perf_counter() - started) * 1000.0
        _obs_record(request.url.path, status_code, duration_ms)

cors_origins, cors_origin_regex, cors_allow_credentials = _resolve_cors_settings()

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_origin_regex=cors_origin_regex,
    allow_credentials=cors_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/signup", response_model=schemas.Token)
def signup(
    request: Request,
    user: schemas.UserCreate,
    response: Response,
    db: Session = Depends(get_db),
):
    db_user = db.query(models.User).filter(models.User.email == user.email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")

    _validate_password_policy(user.password)
    
    hashed_pwd = auth.get_password_hash(user.password)
    new_user = models.User(
        name=user.name,
        email=user.email,
        hashed_password=hashed_pwd,
        role="admin" if _is_admin_email(user.email) else "user",
        email_verified=0,
        token_version=0,
    )
    db.add(new_user)
    db.flush()

    now = _utc_now()
    raw_token = secrets.token_urlsafe(32)
    verification_link = _build_email_verification_link(raw_token)
    db.add(
        models.EmailVerificationToken(
            user_id=new_user.id,
            token_hash=_hash_reset_token(raw_token),
            created_at=now,
            expires_at=now + timedelta(minutes=EMAIL_VERIFICATION_EXPIRE_MINUTES),
            used_at=None,
        )
    )

    access_token, refresh_token = _issue_token_pair(db, new_user, request=request)
    db.commit()
    db.refresh(new_user)

    _send_email_verification(new_user.email, raw_token)

    if APP_ENV.lower() == "development" and not SMTP_HOST:
        print(f"[dev] verification_link={verification_link}")

    _set_auth_cookies(response, access_token, refresh_token)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": new_user,
    }

@app.post("/login", response_model=schemas.Token)
def login(
    request: Request,
    user_credentials: schemas.UserLogin,
    response: Response,
    db: Session = Depends(get_db),
):
    normalized_email = (user_credentials.email or "").strip().lower()
    _enforce_login_abuse_controls(request, normalized_email)

    user = db.query(models.User).filter(models.User.email == user_credentials.email).first()
    if not user or not auth.verify_password(user_credentials.password, user.hashed_password):
        _record_auth_failure(normalized_email, _client_ip(request))
        _append_security_audit_log(
            db,
            event_type="login_failed",
            severity="warn",
            actor_email=normalized_email,
            request=request,
            metadata={"reason": "invalid_credentials"},
        )
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )
    if int(user.is_active or 0) != 1:
        _append_security_audit_log(
            db,
            event_type="login_failed",
            severity="warn",
            actor_user=user,
            target_user=user,
            request=request,
            metadata={"reason": "account_suspended"},
        )
        db.commit()
        raise HTTPException(status_code=403, detail="Account is suspended")
    if REQUIRE_EMAIL_VERIFICATION and int(user.email_verified or 0) != 1:
        _record_auth_failure(normalized_email, _client_ip(request))
        _append_security_audit_log(
            db,
            event_type="login_failed",
            severity="warn",
            actor_user=user,
            target_user=user,
            request=request,
            metadata={"reason": "email_unverified"},
        )
        db.commit()
        raise HTTPException(status_code=403, detail="Email verification is required")

    _clear_auth_failures(normalized_email, _client_ip(request))
    
    access_token, refresh_token = _issue_token_pair(db, user, request=request)
    db.commit()
    _set_auth_cookies(response, access_token, refresh_token)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": user,
    }

@app.post("/update_integrations", response_model=schemas.UserOut)
def update_integrations(
    email: str,
    google: int,
    apple: int,
    current_user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    target_user = db.query(models.User).filter(models.User.email == email).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="User not found")

    _assert_self_or_admin(current_user, target_user.id)
    
    target_user.google_calendar_connected = google
    target_user.apple_health_connected = apple
    db.commit()
    db.refresh(target_user)
    return target_user

@app.post("/forgot-password", response_model=schemas.ForgotPasswordResponse)
def forgot_password(
    request: Request,
    payload: schemas.ForgotPasswordRequest,
    db: Session = Depends(get_db),
):
    _enforce_reset_abuse_controls(request, (payload.email or "").strip().lower())

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
def reset_password(
    request: Request,
    payload: schemas.ResetPasswordRequest,
    db: Session = Depends(get_db),
):
    reset_subject = "reset_token"
    ip_address = _client_ip(request)
    _enforce_auth_lockout(reset_subject, ip_address)
    if ABUSE_CAPTCHA_ENABLED and _is_captcha_required(reset_subject, ip_address):
        if not _verify_abuse_captcha(request):
            raise HTTPException(status_code=429, detail="Captcha required")

    _enforce_reset_abuse_controls(request, "")
    _validate_password_policy(payload.new_password)

    now = datetime.utcnow()
    token_hash = _hash_reset_token(payload.token)
    token_record = db.query(models.PasswordResetToken).filter(
        models.PasswordResetToken.token_hash == token_hash,
        models.PasswordResetToken.used_at.is_(None),
        models.PasswordResetToken.expires_at > now,
    ).first()

    if not token_record:
        _record_auth_failure(reset_subject, ip_address)
        raise HTTPException(status_code=400, detail="Invalid or expired reset token")

    user = db.query(models.User).filter(models.User.id == token_record.user_id).first()
    if not user:
        _record_auth_failure(reset_subject, ip_address)
        raise HTTPException(status_code=400, detail="Invalid reset request")

    user.hashed_password = auth.get_password_hash(payload.new_password)
    user.token_version = int(user.token_version or 0) + 1
    token_record.used_at = now

    _revoke_all_user_sessions(
        db,
        user=user,
        reason="password_reset",
        actor_user=user,
        request=request,
        bump_token_version=False,
    )
    _append_security_audit_log(
        db,
        event_type="password_reset",
        severity="warn",
        actor_user=user,
        target_user=user,
        request=request,
        metadata={"reason": "self_service_reset"},
    )
    db.commit()
    _clear_auth_failures(reset_subject, ip_address)

    return {"message": "Password reset successful. You can now sign in with your new password."}

@app.post("/refresh", response_model=schemas.Token)
def refresh_token(
    request: Request,
    response: Response,
    payload: schemas.RefreshTokenRequest | None = Body(default=None),
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    token = ((payload.refresh_token if payload else None) or "").strip()
    if not token and authorization and authorization.startswith("Bearer "):
        token = authorization.split(" ", 1)[1].strip()
    if not token and AUTH_USE_COOKIES and request is not None:
        token = (request.cookies.get(AUTH_COOKIE_NAME_REFRESH) or "").strip()
    if not token:
        raise HTTPException(status_code=401, detail="Refresh token is required")

    try:
        decoded = auth.decode_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Could not validate credentials")

    if decoded.get("token_type") == "access":
        email = decoded.get("sub")
        token_version = int(decoded.get("tv", 0))
        if not email:
            raise HTTPException(status_code=401, detail="Invalid token payload")

        user = db.query(models.User).filter(models.User.email == email).first()
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        if int(user.is_active or 0) != 1:
            raise HTTPException(status_code=403, detail="Account is suspended")
        if int(user.token_version or 0) != token_version:
            raise HTTPException(status_code=401, detail="Session has been revoked")

        access_token, refresh_token = _issue_token_pair(db, user, request=request)
        db.commit()
        if response is not None:
            _set_auth_cookies(response, access_token, refresh_token)
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "user": user,
        }

    if decoded.get("token_type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid token type")

    email = decoded.get("sub")
    token_jti = decoded.get("jti")
    token_family = decoded.get("fid")
    token_version = int(decoded.get("tv", 0))

    if not email or not token_jti or not token_family:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    user = db.query(models.User).filter(models.User.email == email).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if int(user.is_active or 0) != 1:
        raise HTTPException(status_code=403, detail="Account is suspended")
    if int(user.token_version or 0) != token_version:
        raise HTTPException(status_code=401, detail="Session has been revoked")

    token_hash = _hash_refresh_token(token)
    record = db.query(models.RefreshToken).filter(models.RefreshToken.token_hash == token_hash).first()
    if not record:
        raise HTTPException(status_code=401, detail="Refresh token is invalid")

    if record.revoked_at is not None:
        _revoke_refresh_family(
            db,
            record.family_id,
            "refresh_token_reuse_detected",
            actor_user=user,
            target_user=user,
            request=request,
        )
        db.commit()
        raise HTTPException(status_code=401, detail="Refresh token has been revoked")

    if record.expires_at <= _utc_now():
        record.revoked_at = _utc_now()
        record.revoked_reason = "expired"
        db.commit()
        raise HTTPException(status_code=401, detail="Refresh token has expired")

    access_token, refresh_token = _issue_token_pair(
        db,
        user,
        family_id=record.family_id,
        request=request,
    )
    record.last_used_at = _utc_now()
    record.revoked_at = _utc_now()
    record.replaced_by_jti = auth.decode_token(refresh_token).get("jti")
    record.revoked_reason = "rotated"
    db.commit()

    if response is not None:
        _set_auth_cookies(response, access_token, refresh_token)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": user,
    }


@app.post("/logout", response_model=schemas.MessageResponse)
def logout(
    request: Request,
    response: Response,
    payload: schemas.LogoutRequest | None = Body(default=None),
    current_user: models.User = Depends(_get_current_user),
    token: str = Depends(_extract_bearer_token),
    db: Session = Depends(get_db),
):
    payload = payload or schemas.LogoutRequest()
    _revoke_access_token(db, token, reason="logout", actor_user=current_user, request=request)
    refresh_token = (payload.refresh_token or "").strip()
    if not refresh_token and AUTH_USE_COOKIES and request is not None:
        refresh_token = (request.cookies.get(AUTH_COOKIE_NAME_REFRESH) or "").strip()
    if refresh_token:
        _revoke_refresh_token(
            db,
            refresh_token,
            reason="logout",
            actor_user=current_user,
            request=request,
        )
    _append_security_audit_log(
        db,
        event_type="logout",
        severity="info",
        actor_user=current_user,
        target_user=current_user,
        request=request,
    )
    db.commit()

    if response is not None:
        _clear_auth_cookies(response)
    return {"message": "Logged out successfully"}


def _extract_refresh_token_from_request(request: Request) -> str | None:
    from_header = (request.headers.get("X-Refresh-Token") or "").strip()
    if from_header:
        return from_header
    if AUTH_USE_COOKIES:
        from_cookie = (request.cookies.get(AUTH_COOKIE_NAME_REFRESH) or "").strip()
        if from_cookie:
            return from_cookie
    return None


@app.post("/change-password", response_model=schemas.MessageResponse)
def change_password(
    request: Request,
    payload: schemas.ChangePasswordRequest,
    current_user: models.User = Depends(_get_current_user),
    token: str = Depends(_extract_bearer_token),
    db: Session = Depends(get_db),
):
    if not auth.verify_password(payload.current_password, current_user.hashed_password or ""):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    _validate_password_policy(payload.new_password)
    if auth.verify_password(payload.new_password, current_user.hashed_password or ""):
        raise HTTPException(status_code=400, detail="New password must differ from current password")

    current_user.hashed_password = auth.get_password_hash(payload.new_password)
    _revoke_all_user_sessions(
        db,
        user=current_user,
        reason="password_change",
        actor_user=current_user,
        request=request,
        bump_token_version=True,
    )
    _revoke_access_token(
        db,
        token,
        reason="password_change",
        actor_user=current_user,
        request=request,
    )
    db.commit()
    return {"message": "Password changed. All active sessions were signed out."}


@app.get("/sessions/active", response_model=schemas.SessionInventoryResponse)
def list_my_sessions(
    request: Request,
    current_user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    refresh_token = _extract_refresh_token_from_request(request)
    current_hash = _hash_refresh_token(refresh_token) if refresh_token else None
    return _list_user_sessions_payload(db, user_id=current_user.id, current_refresh_token_hash=current_hash)


@app.delete("/sessions/active/{session_id}", response_model=schemas.MessageResponse)
def revoke_my_session(
    session_id: int,
    request: Request,
    current_user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    session = db.query(models.RefreshToken).filter(
        models.RefreshToken.id == int(session_id),
        models.RefreshToken.user_id == current_user.id,
    ).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if session.revoked_at is None:
        session.revoked_at = _utc_now()
        session.revoked_reason = "user_revoked_session"
        _append_security_audit_log(
            db,
            event_type="session_revoked",
            severity="warn",
            actor_user=current_user,
            target_user=current_user,
            request=request,
            metadata={"session_id": int(session.id)},
        )
        db.commit()

    return {"message": "Session revoked"}


@app.post("/sessions/active/revoke-all", response_model=schemas.MessageResponse)
def revoke_all_my_sessions(
    request: Request,
    current_user: models.User = Depends(_get_current_user),
    token: str = Depends(_extract_bearer_token),
    db: Session = Depends(get_db),
):
    _revoke_all_user_sessions(
        db,
        user=current_user,
        reason="user_revoke_all_sessions",
        actor_user=current_user,
        request=request,
        bump_token_version=True,
    )
    _revoke_access_token(
        db,
        token,
        reason="user_revoke_all_sessions",
        actor_user=current_user,
        request=request,
    )
    db.commit()
    return {"message": "All active sessions were revoked."}


@app.post("/verify-email", response_model=schemas.MessageResponse)
def verify_email(payload: schemas.EmailVerificationRequest, db: Session = Depends(get_db)):
    now = _utc_now()
    token_hash = _hash_reset_token(payload.token)
    token_record = db.query(models.EmailVerificationToken).filter(
        models.EmailVerificationToken.token_hash == token_hash,
        models.EmailVerificationToken.used_at.is_(None),
        models.EmailVerificationToken.expires_at > now,
    ).first()
    if not token_record:
        raise HTTPException(status_code=400, detail="Invalid or expired verification token")

    user = db.query(models.User).filter(models.User.id == token_record.user_id).first()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid verification request")

    user.email_verified = 1
    token_record.used_at = now
    db.commit()
    return {"message": "Email verified successfully"}


@app.post("/resend-email-verification", response_model=schemas.VerificationResponse)
def resend_email_verification(payload: schemas.ResendVerificationRequest, db: Session = Depends(get_db)):
    generic_message = "If an account with that email exists, a verification email has been sent."
    user = db.query(models.User).filter(models.User.email == payload.email).first()
    if not user:
        return {"message": generic_message, "delivery": "email"}
    if int(user.email_verified or 0) == 1:
        return {"message": "Email is already verified", "delivery": "none"}

    now = _utc_now()
    db.query(models.EmailVerificationToken).filter(
        models.EmailVerificationToken.user_id == user.id,
        models.EmailVerificationToken.used_at.is_(None),
    ).update({"used_at": now}, synchronize_session=False)

    raw_token = secrets.token_urlsafe(32)
    verification_link = _build_email_verification_link(raw_token)
    db.add(
        models.EmailVerificationToken(
            user_id=user.id,
            token_hash=_hash_reset_token(raw_token),
            created_at=now,
            expires_at=now + timedelta(minutes=EMAIL_VERIFICATION_EXPIRE_MINUTES),
            used_at=None,
        )
    )
    db.commit()

    delivered = _send_email_verification(user.email, raw_token)
    if APP_ENV.lower() == "development" and not delivered:
        return {
            "message": "Email delivery is unavailable in development. Use the token/link below for testing.",
            "verification_token": raw_token,
            "verification_link": verification_link,
            "delivery": "dev_link",
        }

    return {"message": generic_message, "delivery": "email"}

@app.post("/auth/google", response_model=schemas.Token)
def google_auth(
    request: Request,
    token_data: schemas.SocialAuth,
    response: Response,
    db: Session = Depends(get_db),
):
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
            user = models.User(
                email=email,
                name=name,
                hashed_password="",
                role="admin" if _is_admin_email(email) else "user",
                email_verified=1,
            )
            db.add(user)
            db.commit()
            db.refresh(user)
        else:
            _sync_user_role(user, db=db, actor_user=user, reason="social_auth")
            db.commit()
            db.refresh(user)
        if int(user.is_active or 0) != 1:
            raise HTTPException(status_code=403, detail="Account is suspended")

        access_token, refresh_token = _issue_token_pair(db, user, request=request)
        db.commit()
        _set_auth_cookies(response, access_token, refresh_token)
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "user": user,
        }

    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid Google token")


@app.get("/admin/mfa/setup", response_model=schemas.AdminMfaSetupResponse)
def admin_mfa_setup(user: models.User = Depends(_require_admin), db: Session = Depends(get_db)):
    secret = (user.admin_mfa_secret or "").strip()
    if not secret:
        secret = _generate_totp_secret()
        user.admin_mfa_secret = secret
        db.commit()
        db.refresh(user)

    label = (user.email or "admin").replace(" ", "")
    issuer = ADMIN_MFA_ISSUER.replace(" ", "%20")
    otpauth_url = f"otpauth://totp/{issuer}:{label}?secret={secret}&issuer={issuer}&algorithm=SHA1&digits=6&period=30"
    return {
        "mfa_enabled": bool(user.admin_mfa_enabled),
        "secret": secret,
        "otpauth_url": otpauth_url,
    }


@app.get("/admin/mfa/recovery-codes/status", response_model=schemas.AdminMfaRecoveryCodesStatusResponse)
def admin_mfa_recovery_codes_status(
    user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    total = db.query(models.AdminMfaRecoveryCode).filter(
        models.AdminMfaRecoveryCode.user_id == user.id,
        models.AdminMfaRecoveryCode.replaced_at.is_(None),
    ).count()
    used = db.query(models.AdminMfaRecoveryCode).filter(
        models.AdminMfaRecoveryCode.user_id == user.id,
        models.AdminMfaRecoveryCode.replaced_at.is_(None),
        models.AdminMfaRecoveryCode.used_at.is_not(None),
    ).count()
    remaining = max(0, total - used)
    return {
        "total_codes": int(total),
        "remaining_codes": int(remaining),
        "used_codes": int(used),
    }


@app.post("/admin/re-auth", response_model=schemas.AdminReauthResponse)
def admin_reauth(
    request: Request,
    payload: schemas.AdminReauthRequest,
    user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    if not auth.verify_password(payload.password, user.hashed_password or ""):
        raise HTTPException(status_code=403, detail="Invalid re-auth credentials")

    method = "password"
    if int(user.admin_mfa_enabled or 0) == 1:
        secret = (user.admin_mfa_secret or "").strip()
        has_totp = bool(secret) and _verify_totp(secret, payload.mfa_code or "", window=ADMIN_MFA_WINDOW)
        has_recovery = _redeem_admin_recovery_code(db, user, payload.recovery_code or "")
        if not has_totp and not has_recovery:
            raise HTTPException(status_code=403, detail="Second factor required for admin re-auth")
        method = "totp" if has_totp else "recovery_code"

    now = _utc_now()
    db.query(models.AdminStepUpSession).filter(
        models.AdminStepUpSession.user_id == user.id,
        models.AdminStepUpSession.expires_at <= now,
        models.AdminStepUpSession.used_at.is_(None),
    ).update(
        {"used_at": now, "used_for_action": "expired_cleanup"},
        synchronize_session=False,
    )
    raw_token = secrets.token_urlsafe(32)
    expires_at = now + timedelta(seconds=max(60, ADMIN_STEP_UP_TTL_SECONDS))
    db.add(
        models.AdminStepUpSession(
            user_id=user.id,
            token_hash=_hash_admin_step_up_token(raw_token),
            verified_at=now,
            expires_at=expires_at,
            used_at=None,
            used_for_action=None,
        )
    )
    _append_security_audit_log(
        db,
        event_type="admin_step_up_issued",
        severity="warn",
        actor_user=user,
        target_user=user,
        request=request,
        metadata={"method": method},
    )
    db.commit()
    return {
        "step_up_token": raw_token,
        "expires_at": expires_at.isoformat(),
        "method": method,
    }


@app.post("/admin/mfa/recovery-codes/regenerate", response_model=schemas.AdminMfaRecoveryCodesRegenerateResponse)
def admin_mfa_recovery_codes_regenerate(
    request: Request,
    user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    _require_sensitive_admin_reauth(
        request,
        user,
        db,
        action="admin_mfa_recovery_regenerate",
    )
    if int(user.admin_mfa_enabled or 0) != 1:
        raise HTTPException(status_code=400, detail="Enable admin MFA before generating recovery codes")

    codes = _generate_admin_recovery_codes(db, user)
    _append_security_audit_log(
        db,
        event_type="admin_mfa_recovery_regenerated",
        severity="critical",
        actor_user=user,
        target_user=user,
        request=request,
        metadata={"count": len(codes)},
    )
    db.commit()
    return {
        "message": "Recovery codes generated",
        "codes": codes,
        "total_codes": len(codes),
    }


@app.post("/admin/mfa/enable", response_model=schemas.AdminMfaStatusResponse)
def admin_mfa_enable(
    request: Request,
    payload: schemas.AdminMfaEnableRequest,
    user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    _require_sensitive_admin_reauth(
        request,
        user,
        db,
        action="admin_mfa_enable",
    )
    secret = (user.admin_mfa_secret or "").strip()
    if not secret:
        raise HTTPException(status_code=400, detail="Run setup first")
    if not _verify_totp(secret, payload.code, window=ADMIN_MFA_WINDOW):
        raise HTTPException(status_code=400, detail="Invalid MFA code")

    user.admin_mfa_enabled = 1
    db.commit()
    return {"mfa_enabled": True, "message": "Admin MFA enabled"}


@app.post("/admin/mfa/disable", response_model=schemas.AdminMfaStatusResponse)
def admin_mfa_disable(
    request: Request,
    payload: schemas.AdminMfaDisableRequest,
    user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    _require_sensitive_admin_reauth(
        request,
        user,
        db,
        action="admin_mfa_disable",
    )
    secret = (user.admin_mfa_secret or "").strip()
    if not secret or not _verify_totp(secret, payload.code, window=ADMIN_MFA_WINDOW):
        raise HTTPException(status_code=400, detail="Invalid MFA code")

    now = _utc_now()
    user.admin_mfa_enabled = 0
    user.admin_mfa_secret = None
    db.query(models.AdminMfaRecoveryCode).filter(
        models.AdminMfaRecoveryCode.user_id == user.id,
        models.AdminMfaRecoveryCode.replaced_at.is_(None),
    ).update(
        {"replaced_at": now},
        synchronize_session=False,
    )
    db.query(models.AdminStepUpSession).filter(
        models.AdminStepUpSession.user_id == user.id,
        models.AdminStepUpSession.used_at.is_(None),
        models.AdminStepUpSession.expires_at > now,
    ).update(
        {"used_at": now, "used_for_action": "mfa_disabled"},
        synchronize_session=False,
    )
    db.commit()
    return {"mfa_enabled": False, "message": "Admin MFA disabled"}


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
        "summary": _sanitize_rich_text(payload.summary, max_len=240),
        "description": _sanitize_rich_text(payload.description or "", max_len=5000),
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


@app.post("/uploads/validate", response_model=schemas.UploadValidationResponse)
async def validate_upload(
    file: UploadFile = File(...),
    _: models.User = Depends(_get_current_user),
):
    content_type = (file.content_type or "").strip().lower()
    if content_type not in ALLOWED_UPLOAD_MIME_TYPES:
        raise HTTPException(status_code=400, detail="Unsupported file type")

    content = await file.read(MAX_UPLOAD_BYTES + 1)
    size_bytes = len(content)
    if size_bytes == 0:
        raise HTTPException(status_code=400, detail="Empty file upload")
    if size_bytes > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large")

    if not _validate_upload_magic(content, content_type):
        raise HTTPException(status_code=400, detail="File signature does not match declared type")

    scan_status = _scan_upload_content(content)
    if scan_status != "clean":
        raise HTTPException(status_code=400, detail=f"File rejected: {scan_status}")

    return {
        "filename": file.filename or "upload.bin",
        "content_type": content_type,
        "size_bytes": size_bytes,
        "accepted": True,
        "scan_status": scan_status,
    }


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
    safe_event_type = _sanitize_rich_text(payload.event_type, max_len=64).strip()
    safe_title = _sanitize_rich_text(payload.title, max_len=160).strip()
    safe_body = _sanitize_rich_text(payload.body, max_len=4000).strip()
    if not safe_title or not safe_body or not safe_event_type:
        raise HTTPException(status_code=400, detail="event_type, title and body are required")

    result = _dispatch_push_notification(
        db,
        user_id=user.id,
        event_type=safe_event_type,
        title=safe_title,
        body=safe_body,
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
        "is_admin": _is_admin_user(user),
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


@app.get("/admin/users/{user_id}/sessions", response_model=schemas.SessionInventoryResponse)
def admin_list_user_sessions(
    user_id: int,
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    return _list_user_sessions_payload(db, user_id=target.id)


@app.delete("/admin/users/{user_id}/sessions/{session_id}", response_model=schemas.MessageResponse)
def admin_revoke_user_session(
    user_id: int,
    session_id: int,
    request: Request,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    _require_sensitive_admin_reauth(
        request,
        admin_user,
        db,
        action="admin_user_session_revoke",
    )

    session = db.query(models.RefreshToken).filter(
        models.RefreshToken.id == int(session_id),
        models.RefreshToken.user_id == target.id,
    ).first()
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if session.revoked_at is None:
        session.revoked_at = _utc_now()
        session.revoked_reason = "admin_revoked_session"
        _append_security_audit_log(
            db,
            event_type="session_revoked",
            severity="warn",
            actor_user=admin_user,
            target_user=target,
            request=request,
            metadata={"session_id": int(session.id), "reason": "admin_revoked_session"},
        )
        db.commit()

    return {"message": "Session revoked"}


@app.post("/admin/users/{user_id}/sessions/revoke-all", response_model=schemas.MessageResponse)
def admin_revoke_all_user_sessions(
    user_id: int,
    request: Request,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    _require_sensitive_admin_reauth(
        request,
        admin_user,
        db,
        action="admin_user_sessions_revoke_all",
    )

    _revoke_all_user_sessions(
        db,
        user=target,
        reason="admin_revoke_all_sessions",
        actor_user=admin_user,
        request=request,
        bump_token_version=True,
    )
    db.commit()
    return {"message": "All user sessions revoked"}


@app.delete("/admin/users/{user_id}", response_model=schemas.AdminUserDeleteResponse)
def admin_delete_user(
    user_id: int,
    request: Request,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    if target.id == admin_user.id:
        raise HTTPException(status_code=400, detail="Cannot delete your own admin account")

    _require_sensitive_admin_reauth(
        request,
        admin_user,
        db,
        action="admin_user_delete",
    )

    db.query(models.PasswordResetToken).filter(models.PasswordResetToken.user_id == user_id).delete(synchronize_session=False)
    db.query(models.EmailVerificationToken).filter(models.EmailVerificationToken.user_id == user_id).delete(synchronize_session=False)
    db.query(models.RefreshToken).filter(models.RefreshToken.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AccessTokenBlocklist).filter(models.AccessTokenBlocklist.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AdminMfaRecoveryCode).filter(models.AdminMfaRecoveryCode.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AdminStepUpSession).filter(models.AdminStepUpSession.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AIUsageDaily).filter(models.AIUsageDaily.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AIRequestLog).filter(models.AIRequestLog.user_id == user_id).delete(synchronize_session=False)
    db.query(models.AIJob).filter(models.AIJob.user_id == user_id).delete(synchronize_session=False)
    db.query(models.NotificationDevice).filter(models.NotificationDevice.user_id == user_id).delete(synchronize_session=False)
    db.query(models.NotificationPreference).filter(models.NotificationPreference.user_id == user_id).delete(synchronize_session=False)
    db.query(models.NotificationLog).filter(models.NotificationLog.user_id == user_id).delete(synchronize_session=False)
    db.query(models.GoogleCalendarPendingChange).filter(models.GoogleCalendarPendingChange.user_id == user_id).delete(synchronize_session=False)
    db.query(models.GoogleCalendarEventMirror).filter(models.GoogleCalendarEventMirror.user_id == user_id).delete(synchronize_session=False)
    db.query(models.GoogleCalendarSyncState).filter(models.GoogleCalendarSyncState.user_id == user_id).delete(synchronize_session=False)

    _append_security_audit_log(
        db,
        event_type="user_deleted",
        severity="critical",
        actor_user=admin_user,
        target_user=target,
        request=request,
        metadata={"reason": "admin_delete"},
    )

    db.delete(target)
    db.commit()

    return {
        "user_id": int(user_id),
        "message": "User and related records deleted",
    }


@app.post("/admin/users/{user_id}/suspend", response_model=schemas.AdminUserStateResponse)
def admin_suspend_user(
    user_id: int,
    request: Request,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    if target.id == admin_user.id:
        raise HTTPException(status_code=400, detail="Cannot suspend your own admin account")

    _require_sensitive_admin_reauth(
        request,
        admin_user,
        db,
        action="admin_user_suspend",
    )

    target.is_active = 0
    _revoke_all_user_sessions(
        db,
        user=target,
        reason="account_suspended",
        actor_user=admin_user,
        request=request,
        bump_token_version=True,
    )
    _append_security_audit_log(
        db,
        event_type="user_suspended",
        severity="critical",
        actor_user=admin_user,
        target_user=target,
        request=request,
        metadata={"reason": "admin_suspend"},
    )
    db.commit()

    return {
        "user_id": int(user_id),
        "is_active": False,
        "message": "User suspended",
    }


@app.post("/admin/users/{user_id}/reactivate", response_model=schemas.AdminUserStateResponse)
def admin_reactivate_user(
    user_id: int,
    request: Request,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    _require_sensitive_admin_reauth(
        request,
        admin_user,
        db,
        action="admin_user_reactivate",
    )

    target.is_active = 1
    _append_security_audit_log(
        db,
        event_type="user_reactivated",
        severity="warn",
        actor_user=admin_user,
        target_user=target,
        request=request,
        metadata={"reason": "admin_reactivate"},
    )
    db.commit()

    return {
        "user_id": int(user_id),
        "is_active": True,
        "message": "User reactivated",
    }


@app.patch("/admin/users/{user_id}/role", response_model=schemas.AdminUserRoleResponse)
def admin_update_user_role(
    user_id: int,
    payload: schemas.AdminUserRoleUpdateRequest,
    request: Request,
    admin_user: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    target = db.query(models.User).filter(models.User.id == user_id).first()
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    requested_role = (payload.role or "").strip().lower()
    if requested_role not in {"user", "admin"}:
        raise HTTPException(status_code=400, detail="Role must be either 'user' or 'admin'")

    if target.id == admin_user.id and requested_role != "admin":
        raise HTTPException(status_code=400, detail="Cannot remove your own admin role")

    _require_sensitive_admin_reauth(
        request,
        admin_user,
        db,
        action="admin_user_role_update",
    )

    previous_role = (target.role or "user").strip().lower()
    target.role = requested_role
    if previous_role != requested_role:
        _revoke_all_user_sessions(
            db,
            user=target,
            reason="role_changed",
            actor_user=admin_user,
            request=request,
            bump_token_version=True,
        )
        _append_security_audit_log(
            db,
            event_type="role_changed",
            severity="warn",
            actor_user=admin_user,
            target_user=target,
            request=request,
            metadata={
                "previous_role": previous_role,
                "new_role": requested_role,
                "reason": "admin_update",
            },
        )

    db.commit()

    return {
        "user_id": int(target.id),
        "role": requested_role,
        "message": "User role updated",
    }


@app.get("/admin/audit-logs", response_model=schemas.SecurityAuditLogListResponse)
def admin_list_audit_logs(
    event_type: str = "",
    severity: str = "",
    actor_user_id: int | None = None,
    target_user_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
    _: models.User = Depends(_require_admin),
    db: Session = Depends(get_db),
):
    safe_limit = max(1, min(limit, 200))
    safe_offset = max(0, offset)

    query = db.query(models.SecurityAuditLog)
    normalized_event_type = event_type.strip().lower()
    normalized_severity = severity.strip().lower()
    if normalized_event_type:
        query = query.filter(func.lower(models.SecurityAuditLog.event_type) == normalized_event_type)
    if normalized_severity:
        query = query.filter(func.lower(models.SecurityAuditLog.severity) == normalized_severity)
    if actor_user_id is not None:
        query = query.filter(models.SecurityAuditLog.actor_user_id == actor_user_id)
    if target_user_id is not None:
        query = query.filter(models.SecurityAuditLog.target_user_id == target_user_id)

    total = query.count()
    records = query.order_by(models.SecurityAuditLog.id.desc()).offset(safe_offset).limit(safe_limit).all()

    logs: list[dict] = []
    for record in records:
        metadata: dict = {}
        if (record.metadata_json or "").strip():
            try:
                parsed = json.loads(record.metadata_json)
                if isinstance(parsed, dict):
                    metadata = parsed
            except Exception:
                metadata = {}
        logs.append(
            {
                "event_id": record.event_id,
                "occurred_at": record.occurred_at.isoformat(),
                "event_type": record.event_type,
                "severity": record.severity,
                "actor_user_id": record.actor_user_id,
                "actor_email": record.actor_email,
                "target_user_id": record.target_user_id,
                "ip_address": record.ip_address,
                "user_agent": record.user_agent,
                "metadata": metadata,
                "previous_hash": record.previous_hash,
                "record_hash": record.record_hash,
            }
        )

    return {
        "generated_at": _utc_now().isoformat(),
        "total": int(total),
        "limit": int(safe_limit),
        "offset": int(safe_offset),
        "logs": logs,
    }


@app.post("/ai/analyze-entry", response_model=schemas.AIAnalyzeEntryResponse)
def analyze_entry(
    request: Request,
    payload: schemas.AIAnalyzeEntryRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_ai_abuse_controls(request, user.id)

    payload = payload.model_copy(
        update={
            "transcript": _sanitize_rich_text(payload.transcript, max_len=12000),
            "summary": _sanitize_rich_text(payload.summary, max_len=3000),
            "tags": [_sanitize_rich_text(tag, max_len=80) for tag in (payload.tags or [])],
        }
    )

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
    request: Request,
    payload: schemas.AIWeeklyInsightsRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_ai_abuse_controls(request, user.id)

    payload = payload.model_copy(
        update={
            "entries": [
                entry.model_copy(
                    update={
                        "summary": _sanitize_rich_text(entry.summary, max_len=3000),
                        "ai_summary": _sanitize_rich_text(entry.ai_summary, max_len=3000) if entry.ai_summary else None,
                        "transcript": _sanitize_rich_text(entry.transcript, max_len=12000) if entry.transcript else None,
                        "tags": [_sanitize_rich_text(tag, max_len=80) for tag in (entry.tags or [])],
                    }
                )
                for entry in payload.entries
            ],
            "memory_snippets": [_sanitize_rich_text(snippet, max_len=500) for snippet in (payload.memory_snippets or [])],
        }
    )

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
    request: Request,
    payload: schemas.AIAnalyzeEntryRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_ai_abuse_controls(request, user.id)

    payload = payload.model_copy(
        update={
            "transcript": _sanitize_rich_text(payload.transcript, max_len=12000),
            "summary": _sanitize_rich_text(payload.summary, max_len=3000),
            "tags": [_sanitize_rich_text(tag, max_len=80) for tag in (payload.tags or [])],
        }
    )

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
    request: Request,
    payload: schemas.AIWeeklyInsightsRequest,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_ai_abuse_controls(request, user.id)

    payload = payload.model_copy(
        update={
            "entries": [
                entry.model_copy(
                    update={
                        "summary": _sanitize_rich_text(entry.summary, max_len=3000),
                        "ai_summary": _sanitize_rich_text(entry.ai_summary, max_len=3000) if entry.ai_summary else None,
                        "transcript": _sanitize_rich_text(entry.transcript, max_len=12000) if entry.transcript else None,
                        "tags": [_sanitize_rich_text(tag, max_len=80) for tag in (entry.tags or [])],
                    }
                )
                for entry in payload.entries
            ],
            "memory_snippets": [_sanitize_rich_text(snippet, max_len=500) for snippet in (payload.memory_snippets or [])],
        }
    )

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
    request: Request,
    job_id: str,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_ai_abuse_controls(request, user.id)

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
    request: Request,
    user: models.User = Depends(_get_current_user),
):
    _enforce_ai_abuse_controls(request, user.id)

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
    request: Request,
    job_id: str,
    user: models.User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    _enforce_ai_abuse_controls(request, user.id)

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
