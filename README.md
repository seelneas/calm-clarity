# Calm Clarity
A premium full-stack mobile application for voice journaling, mood tracking, and mindful action items. Built with Flutter and FastAPI.

## 🚀 Features

### Frontend (Flutter)
- **Voice Journaling**: Record thoughts with real-time waveform visualization.
- **Mood Tracking**: Analyze emotional well-being with custom sentiment charts.
- **Dynamic Integrations**: Sync with Google Calendar and Apple Health.
- **Action Items**: AI-generated tasks extracted from your journals.
- **Premium Aesthetics**: Glassmorphism, smooth animations, and optimized light/dark modes.

### Backend (FastAPI)
- **Secure Authentication**: JWT-based login and signup with bcrypt password hashing.
- **Relational Database**: SQLite/SQLAlchemy for persistent user and integration data.
- **API Documentation**: Automatic Swagger docs available at `/docs`.

## 🛠️ Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Python 3.10+](https://www.python.org/downloads/)
- [pip](https://pip.pypa.io/en/stable/installation/)

### Installation & Run

#### 1. Backend Setup
```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
uvicorn main:app --reload
```

#### 1.1 Configure Backend `.env`
Set at minimum:
- `GOOGLE_CLIENT_ID`
- `SECRET_KEY`

Without these, social-auth endpoints return clear configuration errors.

For secure password reset, also configure:
- `FRONTEND_BASE_URL` (e.g., `http://localhost:3000`)
- `RESET_TOKEN_EXPIRE_MINUTES` (default `30`)
- SMTP settings for production email delivery:
	- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`, `SMTP_USE_TLS`

For AI Reflection Coach (Phase 1/2), optional backend variables:
- `AI_PROVIDER` (`auto`, `groq`, `gemini`, `openai`)
- `AI_PROMPT_VERSION` (default `v2`)
- `AI_MAX_TRANSCRIPT_CHARS` (default `4000`)
- `AI_DAILY_QUOTA` (default `40`)
- `AI_JOB_MAX_ATTEMPTS` (default `3`)
- `AI_JOB_POLL_INTERVAL_MS` (default `700`)

Recommended low-cost setup:
- `GROQ_API_KEY`
- `GROQ_MODEL` (default `llama-3.1-8b-instant`)
- `GROQ_BASE_URL` (default `https://api.groq.com/openai/v1`)

Alternative low-cost setup:
- `GEMINI_API_KEY`
- `GEMINI_MODEL` (default `gemini-1.5-flash`)
- `GEMINI_BASE_URL` (default `https://generativelanguage.googleapis.com/v1beta`)

Optional OpenAI setup:
- `OPENAI_API_KEY`
- `OPENAI_MODEL` (default `gpt-4o-mini`)
- `OPENAI_BASE_URL` (default `https://api.openai.com/v1`)

If no provider key is set, the app still works using a deterministic rule-based AI fallback response.

Phase 2 backend endpoints:
- `POST /ai/jobs/analyze-entry`
- `POST /ai/jobs/weekly-insights`
- `GET /ai/jobs/{job_id}`
- `POST /ai/jobs/{job_id}/regenerate`

Guardrails enabled:
- Moderation for self-harm language with crisis resources in response.
- Daily AI quota and transcript length limits.
- Prompt/version/provider metadata logging in backend tables.

Privacy control:
- Frontend now includes an **AI Processing** opt-in toggle in `Settings`.
- When disabled, journal text is not sent to AI endpoints.

Note: In `APP_ENV=development`, if SMTP is not configured, backend returns a temporary reset token in the forgot-password response for local testing.

#### 2. Frontend Setup
```bash
cd calm_clarity
flutter pub get
flutter run \
	--dart-define=API_BASE_URL=http://127.0.0.1:8000 \
	--dart-define=GOOGLE_WEB_CLIENT_ID=your-google-web-client-id.apps.googleusercontent.com
```

For Android emulator, use:

```bash
flutter run \
	--dart-define=API_BASE_URL=http://10.0.2.2:8000 \
	--dart-define=GOOGLE_WEB_CLIENT_ID=your-google-web-client-id.apps.googleusercontent.com
```

#### 3. Running Technique for AI Phase 2 (Async Jobs)
1. Start backend with `uvicorn main:app --reload` (same process handles queue-style jobs via FastAPI background tasks; no separate worker is required).
2. Start Flutter app and sign in.
3. Open `Settings` and enable **AI Processing**.
4. Create a voice entry:
	- App enqueues `analyze-entry` job.
	- Frontend polls `GET /ai/jobs/{job_id}` until `completed`, `blocked`, or `failed`.
5. Open Insights screen:
	- App enqueues `weekly-insights` job and polls for result.
	- App includes **semantic memory snippets** from related past entries to improve weekly coaching context.
	- Use **Regenerate** to enqueue a new job from the previous one.

If AI is blocked by safety checks, crisis resources are returned and shown instead of normal coaching output.

## 📂 Project Structure

- `lib/`: Flutter frontend source code.
- `backend/`: FastAPI backend (auth, models, schemas).
- `assets/`: UI assets, icons, and premium fonts.
- `test/`: Flutter widget and unit tests.

---
Made with clarity • 2026
