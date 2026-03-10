#!/usr/bin/env python3
import argparse
import os
import secrets
import string
from datetime import datetime, timezone


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _new_secret(length: int = 64) -> str:
    alphabet = string.ascii_letters + string.digits + "-_"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def _print_header(title: str) -> None:
    print(f"\n=== {title} ===")


def _print_aws_commands(env: str, jwt_secret: str, admin_api_key: str) -> None:
    prefix = f"calm-clarity/{env}"
    _print_header("AWS Secrets Manager")
    print("# 1) Rotate app-generated secrets")
    print(
        "aws secretsmanager put-secret-value "
        f"--secret-id {prefix}/secret-key --secret-string '{jwt_secret}'"
    )
    print(
        "aws secretsmanager put-secret-value "
        f"--secret-id {prefix}/admin-api-key --secret-string '{admin_api_key}'"
    )
    print("# 2) Store new provider credentials after generating them at the provider")
    print(
        "aws secretsmanager put-secret-value "
        f"--secret-id {prefix}/smtp-password --secret-string '<new-smtp-password>'"
    )
    print(
        "aws secretsmanager put-secret-value "
        f"--secret-id {prefix}/openai-api-key --secret-string '<new-openai-key>'"
    )
    print(
        "aws secretsmanager put-secret-value "
        f"--secret-id {prefix}/groq-api-key --secret-string '<new-groq-key>'"
    )
    print(
        "aws secretsmanager put-secret-value "
        f"--secret-id {prefix}/gemini-api-key --secret-string '<new-gemini-key>'"
    )


def _print_gcp_commands(env: str, jwt_secret: str, admin_api_key: str, project_id: str) -> None:
    prefix = f"calm-clarity-{env}"
    _print_header("Google Secret Manager")
    print("# 1) Rotate app-generated secrets")
    print(
        f"printf '%s' '{jwt_secret}' | gcloud secrets versions add {prefix}-secret-key "
        f"--project {project_id} --data-file=-"
    )
    print(
        f"printf '%s' '{admin_api_key}' | gcloud secrets versions add {prefix}-admin-api-key "
        f"--project {project_id} --data-file=-"
    )
    print("# 2) Store new provider credentials after generating them at the provider")
    print(
        f"printf '%s' '<new-smtp-password>' | gcloud secrets versions add {prefix}-smtp-password "
        f"--project {project_id} --data-file=-"
    )
    print(
        f"printf '%s' '<new-openai-key>' | gcloud secrets versions add {prefix}-openai-api-key "
        f"--project {project_id} --data-file=-"
    )
    print(
        f"printf '%s' '<new-groq-key>' | gcloud secrets versions add {prefix}-groq-api-key "
        f"--project {project_id} --data-file=-"
    )
    print(
        f"printf '%s' '<new-gemini-key>' | gcloud secrets versions add {prefix}-gemini-api-key "
        f"--project {project_id} --data-file=-"
    )


def _print_azure_commands(env: str, jwt_secret: str, admin_api_key: str, vault_name: str) -> None:
    prefix = f"calm-clarity-{env}"
    _print_header("Azure Key Vault")
    print("# 1) Rotate app-generated secrets")
    print(
        "az keyvault secret set "
        f"--vault-name {vault_name} --name {prefix}-secret-key --value '{jwt_secret}'"
    )
    print(
        "az keyvault secret set "
        f"--vault-name {vault_name} --name {prefix}-admin-api-key --value '{admin_api_key}'"
    )
    print("# 2) Store new provider credentials after generating them at the provider")
    print(
        "az keyvault secret set "
        f"--vault-name {vault_name} --name {prefix}-smtp-password --value '<new-smtp-password>'"
    )
    print(
        "az keyvault secret set "
        f"--vault-name {vault_name} --name {prefix}-openai-api-key --value '<new-openai-key>'"
    )
    print(
        "az keyvault secret set "
        f"--vault-name {vault_name} --name {prefix}-groq-api-key --value '<new-groq-key>'"
    )
    print(
        "az keyvault secret set "
        f"--vault-name {vault_name} --name {prefix}-gemini-api-key --value '<new-gemini-key>'"
    )


def _print_vault_commands(env: str, jwt_secret: str, admin_api_key: str) -> None:
    path = f"secret/calm-clarity/{env}/runtime"
    _print_header("HashiCorp Vault")
    print("# 1) Rotate app-generated secrets")
    print(
        "vault kv patch "
        f"{path} SECRET_KEY='{jwt_secret}' ADMIN_API_KEY='{admin_api_key}'"
    )
    print("# 2) Store new provider credentials after generating them at the provider")
    print(
        "vault kv patch "
        f"{path} SMTP_PASSWORD='<new-smtp-password>' OPENAI_API_KEY='<new-openai-key>' "
        "GROQ_API_KEY='<new-groq-key>' GEMINI_API_KEY='<new-gemini-key>'"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a secret rotation plan for Calm Clarity")
    parser.add_argument("--provider", choices=["aws", "gcp", "azure", "vault"], required=True)
    parser.add_argument("--env", default=os.getenv("APP_ENV", "production"))
    parser.add_argument("--project-id", default=os.getenv("GCP_PROJECT_ID", "<gcp-project-id>"))
    parser.add_argument("--vault-name", default=os.getenv("AZURE_KEY_VAULT_NAME", "<azure-vault-name>"))
    parser.add_argument("--print-values", action="store_true", help="Print generated JWT/admin secret values")
    args = parser.parse_args()

    jwt_secret = _new_secret(72)
    admin_api_key = _new_secret(48)

    print(f"Rotation plan generated at {_now_iso()} for env='{args.env}'")

    if args.provider == "aws":
        _print_aws_commands(args.env, jwt_secret, admin_api_key)
    elif args.provider == "gcp":
        _print_gcp_commands(args.env, jwt_secret, admin_api_key, args.project_id)
    elif args.provider == "azure":
        _print_azure_commands(args.env, jwt_secret, admin_api_key, args.vault_name)
    else:
        _print_vault_commands(args.env, jwt_secret, admin_api_key)

    _print_header("Deployment Checklist")
    print("1) Add new secret values/versions in secret manager")
    print("2) Restart API + worker deployments")
    print("3) Verify /health and auth login/refresh flow")
    print("4) Invalidate old credentials with providers where applicable")
    print("5) Record rotation timestamp and operator in your ops log")

    if args.print_values:
        _print_header("Generated Values")
        print(f"SECRET_KEY={jwt_secret}")
        print(f"ADMIN_API_KEY={admin_api_key}")


if __name__ == "__main__":
    main()
