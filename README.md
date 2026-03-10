# Calm Clarity

Calm Clarity is a Flutter + FastAPI app for voice journaling, mood tracking, AI coaching, notifications, and observability.

## What’s in this repo

- `lib/`: Flutter app
- `backend/`: FastAPI API + worker logic
- `backend/tests/`: backend integration tests
- `test/`: Flutter unit/widget tests
- `integration_test/`: Flutter integration tests

## Prerequisites

- Flutter SDK
- Python 3.10+
- `pip`
- (Optional, for queue workers) Redis
- (macOS integration tests) CocoaPods

## Quick Start

### 1) Run backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
```

Backend docs: `http://127.0.0.1:8000/docs`

### 2) Run Flutter app

From repo root:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Android emulator base URL:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## Environment Variables (Minimal)

Set these in backend env for core auth:

- `SECRET_KEY`
- `GOOGLE_CLIENT_ID`

Production recommendation: set secret vars as managed-secret references (`aws-sm://`, `gcp-sm://`, `azure-kv://`, `vault://`, `file://`) and keep `MANAGED_SECRETS_REQUIRED_IN_PRODUCTION=true`.

Optional but common:

- AI provider key(s): `GROQ_API_KEY` or `GEMINI_API_KEY` or `OPENAI_API_KEY`
- Queue mode: `REDIS_URL`, `AI_QUEUE_NAME`
- Admin endpoints: `ADMIN_API_KEY` (optional)

If no AI key is set, backend falls back to rule-based responses.

## Secret Lifecycle Management

- Runtime secret loading is centralized in `backend/secret_manager.py`.
- In production, plaintext secret values are rejected when `MANAGED_SECRETS_REQUIRED_IN_PRODUCTION=true`.
- Supported secret references:
	- `aws-sm://...`
	- `gcp-sm://...`
	- `azure-kv://...`
	- `vault://...`
	- `file://...`

### Rotation workflow

Generate a provider-specific rotation plan from `backend/`:

```bash
python scripts/rotate_secrets.py --provider aws --env production
```

Then follow `docs/security/secret-rotation-runbook.md` to apply, deploy, validate, and rollback safely.

## Queue Worker (Optional, recommended for async AI jobs)

Run in `backend/`:

```bash
python worker_supervisor.py
```

Or single worker:

```bash
python worker.py
```

## Testing

### Backend tests

```bash
cd backend
source .venv/bin/activate
python -m pytest -q
```

### Flutter tests

From repo root:

```bash
flutter test
```

### Integration test (real target)

```bash
flutter test integration_test/observability_e2e_test.dart -d macos
```

## CI

GitHub Actions workflow: `.github/workflows/ci.yml`

- Backend integration tests
- Flutter unit/widget tests
- Flutter integration test on Android emulator

Runs on push to `main` and pull requests.

## Troubleshooting

- **`Invalid key/value pair: DART_DEFINES...` during Pods:** fixed in `macos/Podfile` parser override.
- **Android emulator cannot reach backend:** use `http://10.0.2.2:8000`.
- **Integration test font/network issues:** keep tests independent from runtime font fetching.
- **No AI responses:** verify provider keys or use fallback mode.

---

All Rights Reserved. © 2026
