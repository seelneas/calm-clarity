import json
import os
import subprocess
import time
from dataclasses import dataclass
from typing import Optional

import requests


@dataclass
class _CacheEntry:
    value: str
    expires_at: float


_SECRET_CACHE: dict[str, _CacheEntry] = {}


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _cache_ttl_seconds() -> int:
    raw = os.getenv("SECRET_CACHE_TTL_SECONDS", "300")
    try:
        return max(0, int(raw))
    except ValueError:
        return 300


def _split_ref_and_key(reference: str) -> tuple[str, Optional[str]]:
    if "#" not in reference:
        return reference, None
    base, key = reference.rsplit("#", 1)
    clean_key = key.strip() or None
    return base, clean_key


def _resolve_key_from_json(raw_value: str, key: Optional[str]) -> str:
    if key is None:
        return raw_value

    try:
        parsed = json.loads(raw_value)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"Secret payload is not JSON but key selector was used: #{key}") from error

    if not isinstance(parsed, dict):
        raise RuntimeError(f"Secret payload must be a JSON object for key selector: #{key}")

    if key not in parsed:
        raise RuntimeError(f"Key '{key}' not found in JSON secret payload")

    value = parsed[key]
    if value is None:
        return ""
    return str(value)


def _read_file_secret(reference: str, key: Optional[str]) -> str:
    path = reference[len("file://") :]
    with open(path, "r", encoding="utf-8") as handle:
        raw = handle.read().strip()
    return _resolve_key_from_json(raw, key)


def _run_cli(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        raise RuntimeError(f"Secret CLI command failed: {' '.join(args)} :: {stderr}")
    return (result.stdout or "").strip()


def _read_aws_secret(reference: str, key: Optional[str]) -> str:
    secret_id = reference[len("aws-sm://") :]
    raw = _run_cli(
        [
            "aws",
            "secretsmanager",
            "get-secret-value",
            "--secret-id",
            secret_id,
            "--query",
            "SecretString",
            "--output",
            "text",
        ]
    )
    return _resolve_key_from_json(raw, key)


def _read_gcp_secret(reference: str, key: Optional[str]) -> str:
    # Expected: gcp-sm://<project>/<secret>/<version>
    payload = reference[len("gcp-sm://") :].strip("/")
    parts = payload.split("/")
    if len(parts) != 3:
        raise RuntimeError("gcp-sm reference must be: gcp-sm://<project>/<secret>/<version>")
    project_id, secret_name, version = parts
    raw = _run_cli(
        [
            "gcloud",
            "secrets",
            "versions",
            "access",
            version,
            "--project",
            project_id,
            "--secret",
            secret_name,
        ]
    )
    return _resolve_key_from_json(raw, key)


def _read_azure_secret(reference: str, key: Optional[str]) -> str:
    # Expected: azure-kv://<vault>/<secret> or azure-kv://<vault>/<secret>/<version>
    payload = reference[len("azure-kv://") :].strip("/")
    parts = payload.split("/")
    if len(parts) not in {2, 3}:
        raise RuntimeError("azure-kv reference must be: azure-kv://<vault>/<secret>[/<version>]")

    vault_name, secret_name = parts[0], parts[1]
    args = [
        "az",
        "keyvault",
        "secret",
        "show",
        "--vault-name",
        vault_name,
        "--name",
        secret_name,
        "--query",
        "value",
        "-o",
        "tsv",
    ]
    if len(parts) == 3:
        args.extend(["--version", parts[2]])

    raw = _run_cli(args)
    return _resolve_key_from_json(raw, key)


def _read_vault_secret(reference: str, key: Optional[str]) -> str:
    # Expected: vault://<path>#<field>
    vault_addr = (os.getenv("VAULT_ADDR") or "").strip().rstrip("/")
    vault_token = (os.getenv("VAULT_TOKEN") or "").strip()
    if not vault_addr or not vault_token:
        raise RuntimeError("VAULT_ADDR and VAULT_TOKEN are required for vault:// secret references")

    secret_path = reference[len("vault://") :].strip("/")
    url = f"{vault_addr}/v1/{secret_path}"
    response = requests.get(url, headers={"X-Vault-Token": vault_token}, timeout=10)
    if response.status_code >= 400:
        raise RuntimeError(f"Vault secret fetch failed ({response.status_code}) for path '{secret_path}'")

    payload = response.json()
    data = payload.get("data", {})
    if isinstance(data, dict) and "data" in data and isinstance(data["data"], dict):
        data = data["data"]

    if not isinstance(data, dict):
        raise RuntimeError("Vault response payload is missing expected secret data")

    if key is None:
        if len(data) == 1:
            only_value = next(iter(data.values()))
            return "" if only_value is None else str(only_value)
        raise RuntimeError("vault:// reference requires '#field' when secret has multiple keys")

    if key not in data:
        raise RuntimeError(f"Vault key '{key}' not found in secret data")
    value = data[key]
    return "" if value is None else str(value)


def _fetch_secret_from_reference(reference: str) -> str:
    base_ref, key = _split_ref_and_key(reference.strip())

    if base_ref.startswith("file://"):
        return _read_file_secret(base_ref, key)
    if base_ref.startswith("aws-sm://"):
        return _read_aws_secret(base_ref, key)
    if base_ref.startswith("gcp-sm://"):
        return _read_gcp_secret(base_ref, key)
    if base_ref.startswith("azure-kv://"):
        return _read_azure_secret(base_ref, key)
    if base_ref.startswith("vault://"):
        return _read_vault_secret(base_ref, key)

    raise RuntimeError(
        "Unsupported secret reference scheme. Use one of: file://, aws-sm://, gcp-sm://, azure-kv://, vault://"
    )


def get_runtime_secret(
    env_name: str,
    default: str = "",
    *,
    required: bool = False,
    enforce_managed_ref_in_production: bool = True,
) -> str:
    raw_value = os.getenv(env_name)
    value = (raw_value or "").strip()

    if not value:
        if required and not default:
            raise RuntimeError(f"Missing required secret env var: {env_name}")
        return default

    app_env = (os.getenv("APP_ENV") or "development").strip().lower()
    enforce_refs = _as_bool(os.getenv("MANAGED_SECRETS_REQUIRED_IN_PRODUCTION", "true"), default=True)

    is_reference = value.startswith(("file://", "aws-sm://", "gcp-sm://", "azure-kv://", "vault://"))
    if is_reference:
        cache_key = f"{env_name}:{value}"
        cached = _SECRET_CACHE.get(cache_key)
        now = time.time()
        if cached and cached.expires_at >= now:
            return cached.value

        resolved = _fetch_secret_from_reference(value)
        ttl = _cache_ttl_seconds()
        if ttl > 0:
            _SECRET_CACHE[cache_key] = _CacheEntry(value=resolved, expires_at=now + ttl)
        return resolved

    if enforce_managed_ref_in_production and enforce_refs and app_env == "production":
        raise RuntimeError(
            f"Secret '{env_name}' must use a managed-secret reference in production. "
            "Use: aws-sm://, gcp-sm://, azure-kv://, vault://, or file://"
        )

    return value


def clear_secret_cache() -> None:
    _SECRET_CACHE.clear()
