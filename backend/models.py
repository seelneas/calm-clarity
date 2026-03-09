from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    is_active = Column(Integer, default=1)
    google_calendar_connected = Column(Integer, default=0)  # 0: Not Linked, 1: Connected
    apple_health_connected = Column(Integer, default=0)     # 0: Not Linked, 1: Connected


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    token_hash = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    used_at = Column(DateTime, nullable=True)


class AIJob(Base):
    __tablename__ = "ai_jobs"

    id = Column(String, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    job_type = Column(String, nullable=False, index=True)  # analyze_entry | weekly_insights
    status = Column(String, nullable=False, index=True)  # queued | processing | completed | failed | blocked
    attempts = Column(Integer, nullable=False, default=0)
    max_attempts = Column(Integer, nullable=False, default=3)
    payload_json = Column(Text, nullable=False)
    result_json = Column(Text, nullable=True)
    error_message = Column(Text, nullable=True)
    provider_used = Column(String, nullable=True)
    model_used = Column(String, nullable=True)
    prompt_version = Column(String, nullable=True)
    created_at = Column(DateTime, nullable=False, index=True)
    updated_at = Column(DateTime, nullable=False, index=True)
    completed_at = Column(DateTime, nullable=True)


class AIRequestLog(Base):
    __tablename__ = "ai_request_logs"

    id = Column(String, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    job_id = Column(String, ForeignKey("ai_jobs.id"), nullable=True, index=True)
    request_type = Column(String, nullable=False, index=True)
    status = Column(String, nullable=False, index=True)
    provider = Column(String, nullable=True)
    model = Column(String, nullable=True)
    prompt_version = Column(String, nullable=True)
    input_chars = Column(Integer, nullable=False, default=0)
    output_chars = Column(Integer, nullable=False, default=0)
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=False, index=True)
    completed_at = Column(DateTime, nullable=True)


class AIUsageDaily(Base):
    __tablename__ = "ai_usage_daily"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    usage_date = Column(String, nullable=False, index=True)  # YYYY-MM-DD
    request_count = Column(Integer, nullable=False, default=0)


class NotificationDevice(Base):
    __tablename__ = "notification_devices"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(String, nullable=False, index=True)
    platform = Column(String, nullable=False, index=True)  # android | ios | web | macos | linux | windows
    push_token = Column(String, nullable=False)
    push_enabled = Column(Integer, nullable=False, default=1)
    app_version = Column(String, nullable=True)
    created_at = Column(DateTime, nullable=False, index=True)
    updated_at = Column(DateTime, nullable=False, index=True)
    last_seen_at = Column(DateTime, nullable=False, index=True)


class NotificationPreference(Base):
    __tablename__ = "notification_preferences"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, unique=True, index=True)
    notifications_enabled = Column(Integer, nullable=False, default=1)
    push_enabled = Column(Integer, nullable=False, default=1)
    daily_reminder_enabled = Column(Integer, nullable=False, default=0)
    daily_reminder_hour = Column(Integer, nullable=False, default=20)
    daily_reminder_minute = Column(Integer, nullable=False, default=0)
    timezone = Column(String, nullable=False, default="UTC")
    updated_at = Column(DateTime, nullable=False, index=True)


class NotificationLog(Base):
    __tablename__ = "notification_logs"

    id = Column(String, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    event_type = Column(String, nullable=False, index=True)
    channel = Column(String, nullable=False, index=True)  # push | in_app
    title = Column(String, nullable=False)
    body = Column(Text, nullable=False)
    status = Column(String, nullable=False, index=True)  # sent | failed | skipped
    provider = Column(String, nullable=True)
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=False, index=True)


class GoogleCalendarSyncState(Base):
    __tablename__ = "google_calendar_sync_states"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, unique=True, index=True)
    auto_sync_enabled = Column(Integer, nullable=False, default=1)
    sync_interval_minutes = Column(Integer, nullable=False, default=5)
    last_sync_at = Column(DateTime, nullable=True)
    last_error = Column(Text, nullable=True)
    pull_cursor_iso = Column(String, nullable=True)
    updated_at = Column(DateTime, nullable=False, index=True)


class GoogleCalendarEventMirror(Base):
    __tablename__ = "google_calendar_event_mirrors"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    client_event_id = Column(String, nullable=True, index=True)
    external_event_id = Column(String, nullable=True, index=True)
    summary = Column(String, nullable=False, default="Untitled")
    description = Column(Text, nullable=True)
    status = Column(String, nullable=True, index=True)
    html_link = Column(String, nullable=True)
    start_iso = Column(String, nullable=True)
    end_iso = Column(String, nullable=True)
    timezone = Column(String, nullable=True)
    etag = Column(String, nullable=True)
    updated_remote_iso = Column(String, nullable=True)
    source = Column(String, nullable=False, default="google")
    deleted = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, nullable=False, index=True)
    updated_at = Column(DateTime, nullable=False, index=True)


class GoogleCalendarPendingChange(Base):
    __tablename__ = "google_calendar_pending_changes"

    id = Column(String, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    action = Column(String, nullable=False, index=True)  # create | update | delete
    client_event_id = Column(String, nullable=True, index=True)
    external_event_id = Column(String, nullable=True, index=True)
    payload_json = Column(Text, nullable=True)
    status = Column(String, nullable=False, default="pending", index=True)  # pending | applied | failed
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, nullable=False, index=True)
    updated_at = Column(DateTime, nullable=False, index=True)
