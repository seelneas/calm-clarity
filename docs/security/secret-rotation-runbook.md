# Secret Rotation Runbook

This runbook covers runtime secrets for the backend:

- `SECRET_KEY` (JWT signing)
- `ADMIN_API_KEY`
- `SMTP_USERNAME` / `SMTP_PASSWORD`
- `OPENAI_API_KEY`, `GROQ_API_KEY`, `GEMINI_API_KEY`
- `FCM_SERVER_KEY`
- `ABUSE_CAPTCHA_SECRET_KEY`

## 1) Pre-rotation checks

1. Confirm `APP_ENV=production` and `MANAGED_SECRETS_REQUIRED_IN_PRODUCTION=true`.
2. Verify all secret env vars are references (`aws-sm://`, `gcp-sm://`, `azure-kv://`, `vault://`, `file://`) not plaintext.
3. Ensure rollback plan is ready (previous secret versions retained).

## 2) Generate a rotation plan

From `backend/`:

```bash
python scripts/rotate_secrets.py --provider aws --env production
```

Provider options: `aws`, `gcp`, `azure`, `vault`.

The command prints provider-specific update commands and deployment checklist steps.

## 3) Rotate secrets

1. Rotate app-generated secrets first (`SECRET_KEY`, `ADMIN_API_KEY`).
2. Rotate provider-managed credentials (SMTP and AI/API keys) in their upstream providers.
3. Store the new credential values as new versions in your secret manager.

## 4) Deploy and validate

1. Restart API and worker deployments.
2. Validate:
   - `/health` endpoint
   - login and refresh token flow
   - admin-auth endpoints
   - password reset/verification email flow
   - AI endpoints and push notifications

## 5) Post-rotation hardening

1. Disable or revoke old provider credentials.
2. Record rotation metadata (who, when, what) in your ops log.
3. Schedule next rotation window.

## Rollback

If a rotated secret causes incidents:

1. Repoint the secret reference to the previous known-good version.
2. Restart API and workers.
3. Re-run validation checks.
4. Open an incident review for root-cause analysis.
