import importlib
import logging
import os
import uuid
from typing import Any

from secret_manager import get_runtime_secret

logger = logging.getLogger(__name__)

SUPABASE_URL = (os.getenv("SUPABASE_URL", "") or "").strip()
SUPABASE_SERVICE_ROLE_KEY = (
    get_runtime_secret(
        "SUPABASE_SERVICE_ROLE_KEY",
        default="",
        enforce_managed_ref_in_production=True,
    )
    or ""
).strip()
SUPABASE_STORAGE_BUCKET = (
    os.getenv("SUPABASE_STORAGE_BUCKET", "calm-clarity-media") or ""
).strip()
SUPABASE_SIGNED_URL_TTL_SECONDS = int(
    os.getenv("SUPABASE_SIGNED_URL_TTL_SECONDS", "31536000")
)

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


def _extract_url(value: Any) -> str:
    if value is None:
        return ""

    if isinstance(value, str):
        return value.strip()

    if isinstance(value, dict):
        direct = (
            value.get("publicUrl")
            or value.get("public_url")
            or value.get("signedURL")
            or value.get("signed_url")
            or value.get("url")
        )
        if isinstance(direct, str) and direct.strip():
            return direct.strip()

        nested_data = value.get("data")
        if nested_data is not None:
            nested = _extract_url(nested_data)
            if nested:
                return nested
        return ""

    data_attr = getattr(value, "data", None)
    if data_attr is not None:
        nested = _extract_url(data_attr)
        if nested:
            return nested

    for attr_name in ("public_url", "publicUrl", "signed_url", "signedURL", "url"):
        attr_value = getattr(value, attr_name, None)
        if isinstance(attr_value, str) and attr_value.strip():
            return attr_value.strip()

    return ""


def _normalize_absolute_url(url: str) -> str:
    normalized = (url or "").strip()
    if not normalized:
        return ""

    lowered = normalized.lower()
    if lowered.startswith("http://") or lowered.startswith("https://"):
        return normalized

    base = SUPABASE_URL.rstrip("/")
    if not base:
        return normalized

    if normalized.startswith("/"):
        return f"{base}{normalized}"

    return f"{base}/{normalized}"


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

    # ── Resolve an accessible URL ──
    # Prefer a signed URL because it works for BOTH public and private buckets.
    # bucket.get_public_url() always returns a well-formed URL (it only
    # constructs the path), so it never fails — but the resulting URL returns
    # 400 / 403 if the bucket is private (the Supabase default).
    resolved_url = ""

    # 1. Try a long-lived signed URL first (works for private AND public buckets)
    try:
        signed_result = bucket.create_signed_url(
            object_path,
            max(60, SUPABASE_SIGNED_URL_TTL_SECONDS),
        )
        resolved_url = _normalize_absolute_url(_extract_url(signed_result))
        if resolved_url:
            logger.info(
                "Signed URL created for %s/%s: %s",
                media_type,
                object_path,
                resolved_url[:120],
            )
    except Exception as exc:
        logger.warning("Signed URL creation failed for %s: %s", object_path, exc)

    # 2. Fall back to the public URL (only works if the bucket is public)
    if not resolved_url:
        resolved_url = _normalize_absolute_url(
            _extract_url(bucket.get_public_url(object_path))
        )
        if resolved_url:
            logger.info(
                "Using public URL fallback for %s/%s: %s",
                media_type,
                object_path,
                resolved_url[:120],
            )

    # 3. Last resort: construct the URL manually
    if not resolved_url:
        object_path_no_leading = object_path.lstrip("/")
        resolved_url = (
            f"{SUPABASE_URL}/storage/v1/object/public/"
            f"{SUPABASE_STORAGE_BUCKET}/{object_path_no_leading}"
        )
        logger.info(
            "Using manually constructed URL for %s/%s: %s",
            media_type,
            object_path,
            resolved_url[:120],
        )

    return {
        "bucket": SUPABASE_STORAGE_BUCKET,
        "storage_path": object_path,
        "public_url": resolved_url,
    }


def refresh_media_url(existing_url: str) -> str:
    """Re-sign an existing Supabase Storage URL.

    If the URL looks like a public-path URL for this bucket, extract the
    object path and create a fresh signed URL that works regardless of
    whether the bucket is public or private.

    Returns the refreshed URL, or the original URL unchanged if
    refreshing is not possible (e.g. not a Supabase URL, or storage is
    not configured).
    """
    raw = (existing_url or "").strip()
    if not raw:
        return raw

    if not is_supabase_storage_enabled():
        return raw

    # Only attempt to refresh URLs that belong to our Supabase project
    base = SUPABASE_URL.rstrip("/").lower()
    if not raw.lower().startswith(base):
        return raw

    # Extract the object path from the URL.
    # Possible patterns:
    #   .../storage/v1/object/public/<bucket>/<path>
    #   .../storage/v1/object/sign/<bucket>/<path>?token=...
    #   .../storage/v1/object/<bucket>/<path>
    bucket = SUPABASE_STORAGE_BUCKET
    markers = [
        f"/storage/v1/object/public/{bucket}/",
        f"/storage/v1/object/sign/{bucket}/",
        f"/storage/v1/object/{bucket}/",
    ]

    object_path: str | None = None
    for marker in markers:
        idx = raw.lower().find(marker.lower())
        if idx >= 0:
            remainder = raw[idx + len(marker):]
            # Strip ?token=... query string if present
            if "?" in remainder:
                remainder = remainder.split("?", 1)[0]
            object_path = remainder.strip("/")
            break

    if not object_path:
        return raw

    try:
        client = get_supabase_client()
        bucket_ref = client.storage.from_(SUPABASE_STORAGE_BUCKET)
        signed_result = bucket_ref.create_signed_url(
            object_path,
            max(60, SUPABASE_SIGNED_URL_TTL_SECONDS),
        )
        refreshed = _normalize_absolute_url(_extract_url(signed_result))
        if refreshed:
            logger.info("Refreshed URL for %s → %s", object_path, refreshed[:120])
            return refreshed
    except Exception as exc:
        logger.warning("Failed to refresh URL for %s: %s", object_path, exc)

    return raw
