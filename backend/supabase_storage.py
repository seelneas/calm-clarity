import os
import uuid
import importlib
from typing import Any

from secret_manager import get_runtime_secret

SUPABASE_URL = (os.getenv("SUPABASE_URL", "") or "").strip()
SUPABASE_SERVICE_ROLE_KEY = get_runtime_secret(
    "SUPABASE_SERVICE_ROLE_KEY",
    default="",
    enforce_managed_ref_in_production=True,
).strip()
SUPABASE_STORAGE_BUCKET = (os.getenv("SUPABASE_STORAGE_BUCKET", "calm-clarity-media") or "").strip()

_ALLOWED_EXTENSIONS = {
    "image/jpeg": ".jpeg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "audio/mp4": ".m4a",
    "audio/m4a": ".m4a",
    "audio/aac": ".aac",
    "audio/mpeg": ".mp3",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/webm": ".webm",
}

_supabase_client: Any | None = None


def is_supabase_storage_enabled() -> bool:
    return bool(SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY and SUPABASE_STORAGE_BUCKET)


def _require_configured() -> None:
    try:
        importlib.import_module("supabase")
    except Exception as exc:
        raise RuntimeError("supabase package is not installed") from exc

    if not is_supabase_storage_enabled():
        raise RuntimeError("Supabase storage is not configured")


def _create_client_dynamic(url: str, key: str) -> Any:
    module = importlib.import_module("supabase")
    create_client = getattr(module, "create_client", None)
    if create_client is None:
        raise RuntimeError("supabase package is not installed")
    return create_client(url, key)


def get_supabase_client() -> Any:
    global _supabase_client
    _require_configured()

    if _supabase_client is None:
        _supabase_client = _create_client_dynamic(
            SUPABASE_URL,
            SUPABASE_SERVICE_ROLE_KEY,
        )
    return _supabase_client


def _safe_extension(content_type: str, original_filename: str | None) -> str:
    mapped = _ALLOWED_EXTENSIONS.get((content_type or "").strip().lower())
    if mapped:
        return mapped

    filename = (original_filename or "").strip()
    if "." in filename:
        return f".{filename.rsplit('.', 1)[-1].lower()}"
    return ".bin"


def upload_user_media(
    *,
    user_id: int,
    media_type: str,
    content_type: str,
    content: bytes,
    original_filename: str | None,
) -> dict[str, str]:
    if media_type not in {"profile", "voice"}:
        raise ValueError("Invalid media_type")

    client = get_supabase_client()

    extension = _safe_extension(content_type, original_filename)
    object_path = (
        f"users/{user_id}/{media_type}/"
        f"{uuid.uuid4().hex}{extension}"
    )

    options = {
        "content-type": content_type,
        "upsert": "false",
    }

    bucket = client.storage.from_(SUPABASE_STORAGE_BUCKET)
    bucket.upload(object_path, content, options)

    public_url = bucket.get_public_url(object_path)
    if isinstance(public_url, dict):
        public_url = public_url.get("publicUrl") or public_url.get("public_url") or ""

    return {
        "bucket": SUPABASE_STORAGE_BUCKET,
        "storage_path": object_path,
        "public_url": str(public_url),
    }
