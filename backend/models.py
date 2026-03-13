from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    role = Column(String, default="user")
    is_active = Column(Integer, default=1)
    email_verified = Column(Integer, default=0)
    token_version = Column(Integer, default=0)
    admin_mfa_enabled = Column(Integer, default=0)
    admin_mfa_secret = Column(String, nullable=True)
    apple_health_connected = Column(Integer, default=0)     # 0: Not Linked, 1: Connected


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    token_hash = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    used_at = Column(DateTime, nullable=True)


class EmailVerificationToken(Base):
    __tablename__ = "email_verification_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    token_hash = Column(String, unique=True, index=True, nullable=False)
    created_at = Column(DateTime, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    used_at = Column(DateTime, nullable=True)


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    jti = Column(String, unique=True, index=True, nullable=False)
    family_id = Column(String, index=True, nullable=False)
    token_hash = Column(String, unique=True, index=True, nullable=False)
    issued_at = Column(DateTime, nullable=False, index=True)
    expires_at = Column(DateTime, nullable=False, index=True)
    last_used_at = Column(DateTime, nullable=True, index=True)
    client_ip = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    device_label = Column(String, nullable=True)
    revoked_at = Column(DateTime, nullable=True, index=True)
    replaced_by_jti = Column(String, nullable=True)
    revoked_reason = Column(String, nullable=True)


class AccessTokenBlocklist(Base):
    __tablename__ = "access_token_blocklist"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    jti = Column(String, unique=True, index=True, nullable=False)
    expires_at = Column(DateTime, nullable=False, index=True)
    revoked_at = Column(DateTime, nullable=False, index=True)
    revoked_reason = Column(String, nullable=True)


class SecurityAuditLog(Base):
    __tablename__ = "security_audit_logs"

    id = Column(Integer, primary_key=True, index=True)
    event_id = Column(String, unique=True, index=True, nullable=False)
    occurred_at = Column(DateTime, nullable=False, index=True)
    event_type = Column(String, nullable=False, index=True)
    severity = Column(String, nullable=False, index=True)  # info | warn | critical
    actor_user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    actor_email = Column(String, nullable=True, index=True)
    target_user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    metadata_json = Column(Text, nullable=True)
    previous_hash = Column(String, nullable=True)
    record_hash = Column(String, nullable=False, index=True)


class AdminMfaRecoveryCode(Base):
    __tablename__ = "admin_mfa_recovery_codes"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    code_hash = Column(String, nullable=False, index=True)
    created_at = Column(DateTime, nullable=False, index=True)
    used_at = Column(DateTime, nullable=True, index=True)
    replaced_at = Column(DateTime, nullable=True, index=True)


class AdminStepUpSession(Base):
    __tablename__ = "admin_step_up_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    token_hash = Column(String, nullable=False, unique=True, index=True)
    verified_at = Column(DateTime, nullable=False, index=True)
    expires_at = Column(DateTime, nullable=False, index=True)
    used_at = Column(DateTime, nullable=True, index=True)
    used_for_action = Column(String, nullable=True)


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


