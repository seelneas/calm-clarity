from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
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
