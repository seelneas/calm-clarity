from fastapi import FastAPI, Depends, HTTPException, status, Header, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
import os
import secrets
import hashlib
import smtplib
import json
import uuid
from datetime import datetime, timedelta
from email.message import EmailMessage
from dotenv import load_dotenv
from sqlalchemy.orm import Session
from database import engine, Base, get_db, SessionLocal
import models, schemas, auth
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
import requests

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

SMTP_HOST = os.getenv("SMTP_HOST")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("SMTP_USERNAME")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USERNAME or "")
SMTP_USE_TLS = os.getenv("SMTP_USE_TLS", "true").lower() in {"1", "true", "yes"}


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


def _retrieve_memory_snippets(entries: list[schemas.AIWeeklyEntryInput], limit: int = 5) -> list[str]:
    if not entries:
        return []

    combined_query = " ".join([f"{entry.summary} {entry.ai_summary or ''} {' '.join(entry.tags)}" for entry in entries])
    query_terms = _tokenize_text(combined_query)
    scored: list[tuple[float, str]] = []

    for entry in entries:
        candidate = f"{entry.summary} {entry.ai_summary or ''} {' '.join(entry.tags)}".strip()
        terms = _tokenize_text(candidate)
        overlap = len(query_terms.intersection(terms))
        score = float(overlap)
        if score > 0:
            scored.append((score, candidate))

    scored.sort(key=lambda item: item[0], reverse=True)
    snippets = []
    for _, text in scored[: max(1, limit)]:
        clipped = text[:160].strip()
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
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(entries)
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
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(payload.entries)

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
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(payload.entries)

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
    memory_snippets = [snippet.strip() for snippet in (payload.memory_snippets or []) if snippet.strip()]
    if not memory_snippets:
        memory_snippets = _retrieve_memory_snippets(payload.entries)

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

        job.status = "processing"
        job.updated_at = _utc_now()
        db.commit()

        payload_data = json.loads(job.payload_json)
        user_id = job.user_id
        request_type = job.job_type
        input_chars = len(job.payload_json)

        for attempt in range(job.attempts + 1, job.max_attempts + 1):
            job.attempts = attempt
            job.updated_at = _utc_now()
            db.commit()

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
                last_error = str(error)
                if attempt >= job.max_attempts:
                    job.status = "failed"
                    job.error_message = last_error[:500]
                    job.updated_at = _utc_now()
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

        db.commit()
    finally:
        db.close()

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Calm Clarity Backend")

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
def refresh_token(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
        
    token = authorization.split(" ")[1]
    
    try:
        payload = auth.jwt.decode(token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM], options={"verify_signature": False})
        email: str = payload.get("sub")
        if email is None:
            raise HTTPException(status_code=401, detail="Invalid token")
            
        # Create a new token
        access_token = auth.create_access_token(data={"sub": email})
        return {"access_token": access_token, "token_type": "bearer"}
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

        access_token = auth.create_access_token(data={"sub": user.email})
        return {"access_token": access_token, "token_type": "bearer", "user": user}

    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid Google token")


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
    background_tasks: BackgroundTasks,
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

    background_tasks.add_task(_process_ai_job, job.id)
    return {
        "job_id": job.id,
        "status": job.status,
        "queued_at": now.isoformat(),
    }


@app.post("/ai/jobs/weekly-insights", response_model=schemas.AIJobCreateResponse)
def enqueue_weekly_insights(
    payload: schemas.AIWeeklyInsightsRequest,
    background_tasks: BackgroundTasks,
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

    background_tasks.add_task(_process_ai_job, job.id)
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


@app.post("/ai/jobs/{job_id}/regenerate", response_model=schemas.AIJobCreateResponse)
def regenerate_ai_job(
    job_id: str,
    background_tasks: BackgroundTasks,
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

    background_tasks.add_task(_process_ai_job, new_job.id)
    return {
        "job_id": new_job.id,
        "status": new_job.status,
        "queued_at": now.isoformat(),
    }

@app.get("/")
def read_root():
    return {"message": "Calm Clarity API is running"}
