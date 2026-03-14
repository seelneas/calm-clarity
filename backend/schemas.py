from pydantic import BaseModel, EmailStr, Field, ConfigDict
from typing import Optional, List


class StrictRequestModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

class UserBase(BaseModel):
    email: EmailStr
    name: Optional[str] = None
    role: str = "user"
    apple_health_connected: int = 0
    profile_photo_url: Optional[str] = None

class UserCreate(UserBase):
    password: str = Field(min_length=8, max_length=256)

class UserLogin(StrictRequestModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=256)

class UserOut(UserBase):
    id: int

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str
    user: UserOut

class SocialAuth(StrictRequestModel):
    token: Optional[str] = Field(default=None, min_length=0, max_length=4096)
    access_token: Optional[str] = Field(default=None, min_length=0, max_length=4096)
    name: Optional[str] = Field(default=None, max_length=120)
    email: Optional[str] = None
    provider: str = Field(min_length=3, max_length=20) # 'google' or 'apple'


class ForgotPasswordRequest(StrictRequestModel):
    email: EmailStr


class ForgotPasswordResponse(BaseModel):
    message: str
    reset_token: Optional[str] = None
    reset_link: Optional[str] = None
    delivery: Optional[str] = None


class ResetPasswordRequest(StrictRequestModel):
    token: str = Field(min_length=16, max_length=512)
    new_password: str = Field(min_length=8, max_length=256)


class RefreshTokenRequest(StrictRequestModel):
    refresh_token: Optional[str] = Field(default=None, min_length=16, max_length=4096)


class LogoutRequest(StrictRequestModel):
    refresh_token: Optional[str] = Field(default=None, min_length=16, max_length=4096)


class ChangePasswordRequest(StrictRequestModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=8, max_length=256)


class SessionItem(BaseModel):
    session_id: int
    issued_at: str
    expires_at: str
    last_used_at: Optional[str] = None
    revoked_at: Optional[str] = None
    revoked_reason: Optional[str] = None
    client_ip: Optional[str] = None
    user_agent: Optional[str] = None
    device_label: Optional[str] = None
    current: bool = False


class DeviceItem(BaseModel):
    id: int
    device_id: str
    platform: str
    push_enabled: bool
    app_version: Optional[str] = None
    last_seen_at: Optional[str] = None


class SessionInventoryResponse(BaseModel):
    generated_at: str
    total_sessions: int
    active_sessions: int
    sessions: List[SessionItem]
    devices: List[DeviceItem]


class AdminMfaSetupResponse(BaseModel):
    mfa_enabled: bool
    secret: str
    otpauth_url: str


class AdminMfaEnableRequest(StrictRequestModel):
    code: str = Field(min_length=6, max_length=8)


class AdminMfaDisableRequest(StrictRequestModel):
    code: str = Field(min_length=6, max_length=8)


class AdminMfaStatusResponse(BaseModel):
    mfa_enabled: bool
    message: str


class AdminMfaRecoveryCodesStatusResponse(BaseModel):
    total_codes: int
    remaining_codes: int
    used_codes: int


class AdminMfaRecoveryCodesRegenerateResponse(BaseModel):
    message: str
    codes: List[str]
    total_codes: int


class AdminReauthRequest(StrictRequestModel):
    password: str = Field(min_length=1, max_length=256)
    mfa_code: Optional[str] = Field(default=None, min_length=6, max_length=8)
    recovery_code: Optional[str] = Field(default=None, min_length=6, max_length=64)


class AdminReauthResponse(BaseModel):
    step_up_token: str
    expires_at: str
    method: str


class MessageResponse(BaseModel):
    message: str


class AdminAccessResponse(BaseModel):
    is_admin: bool
    email: EmailStr


class AdminUserSummaryResponse(BaseModel):
    generated_at: str
    total_users: int
    users_with_apple_health: int
    users_active_last_7_days: int
    ai_requests_last_7_days: int
    ai_requests_today: int


class AdminUserListItem(BaseModel):
    id: int
    name: Optional[str] = None
    email: EmailStr
    is_active: bool
    apple_health_connected: bool
    ai_requests_last_7_days: int
    ai_requests_today: int
    push_devices_active: int
    last_seen_at: Optional[str] = None
    created_at: Optional[str] = None


class AdminUserListResponse(BaseModel):
    generated_at: str
    total: int
    limit: int
    offset: int
    users: List[AdminUserListItem]


class AdminUserDeleteResponse(BaseModel):
    user_id: int
    message: str


class AdminUserStateResponse(BaseModel):
    user_id: int
    is_active: bool
    message: str


class AdminUserRoleUpdateRequest(StrictRequestModel):
    role: str = Field(min_length=4, max_length=20)


class AdminUserRoleResponse(BaseModel):
    user_id: int
    role: str
    message: str


class SecurityAuditLogItem(BaseModel):
    event_id: str
    occurred_at: str
    event_type: str
    severity: str
    actor_user_id: Optional[int] = None
    actor_email: Optional[str] = None
    target_user_id: Optional[int] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    metadata: dict = Field(default_factory=dict)
    previous_hash: Optional[str] = None
    record_hash: str


class SecurityAuditLogListResponse(BaseModel):
    generated_at: str
    total: int
    limit: int
    offset: int
    logs: List[SecurityAuditLogItem]


class AIAnalyzeEntryRequest(StrictRequestModel):
    transcript: str = Field(default="", max_length=12000)
    summary: str = Field(default="", max_length=3000)
    mood: str = Field(min_length=2, max_length=40)
    mood_confidence: Optional[float] = None
    tags: List[str] = Field(default_factory=list, max_length=30)


class AIAnalyzeEntryResponse(BaseModel):
    ai_summary: str = Field(min_length=1)
    ai_action_items: List[str]
    ai_mood_explanation: str = Field(min_length=1)
    ai_followup_prompt: str = Field(min_length=1)
    safety_flag: bool = False
    crisis_resources: List[str] = []


class AIWeeklyEntryInput(StrictRequestModel):
    timestamp: str = Field(min_length=5, max_length=64)
    summary: str = Field(max_length=3000)
    mood: str = Field(min_length=2, max_length=40)
    tags: List[str] = Field(default_factory=list, max_length=30)
    ai_summary: Optional[str] = Field(default=None, max_length=3000)
    transcript: Optional[str] = Field(default=None, max_length=12000)


class AIWeeklyInsightsRequest(StrictRequestModel):
    timeframe_label: Optional[str] = Field(default=None, max_length=80)
    entries: List[AIWeeklyEntryInput] = Field(min_length=1, max_length=90)
    memory_candidates: List[AIWeeklyEntryInput] = Field(default_factory=list, max_length=120)
    memory_snippets: List[str] = Field(default_factory=list, max_length=120)


class AIWeeklyInsightsResponse(BaseModel):
    weekly_summary: str = Field(min_length=1)
    key_patterns: List[str]
    coaching_priorities: List[str]
    next_week_prompt: str = Field(min_length=1)
    memory_snippets_used: List[str] = []
    safety_flag: bool = False
    crisis_resources: List[str] = []


class AIJobCreateResponse(BaseModel):
    job_id: str
    status: str
    queued_at: str


class AIJobStatusResponse(BaseModel):
    job_id: str
    job_type: str
    status: str
    attempts: int
    max_attempts: int
    error_message: Optional[str] = None
    result: Optional[dict] = None
    provider_used: Optional[str] = None
    model_used: Optional[str] = None
    prompt_version: Optional[str] = None
    updated_at: str


class AIQueueHealthResponse(BaseModel):
    queue_name: str
    queued_count: int
    started_count: int
    failed_count: int


class AIFailedJobItem(BaseModel):
    job_id: str
    user_id: int
    job_type: str
    status: str
    attempts: int
    max_attempts: int
    error_message: Optional[str] = None
    provider_used: Optional[str] = None
    model_used: Optional[str] = None
    created_at: str
    updated_at: str


class AIQueueDepthMetrics(BaseModel):
    queue_name: str
    queued_count: int
    started_count: int
    failed_registry_count: int


class AIJobStatusMetrics(BaseModel):
    total: int
    queued: int
    processing: int
    completed: int
    failed: int
    blocked: int


class AIRetryMetrics(BaseModel):
    jobs_with_retry: int
    total_retry_attempts: int
    exhausted_jobs: int


class AIModerationMetrics(BaseModel):
    blocked_jobs: int
    blocked_requests: int


class AIQuotaDailyPoint(BaseModel):
    usage_date: str
    request_count: int


class AIQuotaTopUser(BaseModel):
    user_id: int
    email: Optional[str] = None
    request_count: int


class AIQuotaUsageMetrics(BaseModel):
    daily_quota_limit: int
    today_request_count: int
    today_unique_users: int
    window_request_count: int
    window_unique_users: int
    daily_series: List[AIQuotaDailyPoint]
    top_users: List[AIQuotaTopUser]


class AIOpsDashboardResponse(BaseModel):
    generated_at: str
    window_days: int
    queue_depth: AIQueueDepthMetrics
    job_status: AIJobStatusMetrics
    retries: AIRetryMetrics
    moderation: AIModerationMetrics
    quota: AIQuotaUsageMetrics
    failed_jobs: List[AIFailedJobItem]


class AIWorkerHeartbeatItem(BaseModel):
    worker_key: str
    ttl_seconds: int
    stale: bool


class AIDeadLetterListResponse(BaseModel):
    generated_at: str
    queue_name: str
    total_failed_jobs: int
    jobs: List[AIFailedJobItem]


class AIDeadLetterActionResponse(BaseModel):
    job_id: str
    status: str
    message: str


class AIReliabilityCheckItem(BaseModel):
    name: str
    status: str
    detail: str


class AIReliabilityValidationResponse(BaseModel):
    generated_at: str
    overall_status: str
    checks: List[AIReliabilityCheckItem]
    queue_name: str
    heartbeat_workers: List[AIWorkerHeartbeatItem]


class ObservabilityTopPath(BaseModel):
    path: str
    count: int


class ObservabilityTrafficMetrics(BaseModel):
    window_seconds: int
    request_count: int
    error_count: int
    error_rate: float
    requests_per_second: float
    latency_p50_ms: float
    latency_p95_ms: float
    latency_avg_ms: float
    top_paths: List[ObservabilityTopPath]


class ObservabilityIncidentSignal(BaseModel):
    signal: str
    severity: str
    detail: str


class ObservabilityDashboardResponse(BaseModel):
    generated_at: str
    service_status: str
    traffic: ObservabilityTrafficMetrics
    ai_queue_depth: int
    ai_failed_registry: int
    notification_recent_failed: int
    notification_recent_sent: int
    signals: List[ObservabilityIncidentSignal]


class ObservabilityAlertItem(BaseModel):
    name: str
    status: str
    detail: str


class ObservabilityAlertsResponse(BaseModel):
    generated_at: str
    overall_status: str
    alerts: List[ObservabilityAlertItem]


class NotificationDeviceRegisterRequest(StrictRequestModel):
    device_id: str = Field(min_length=2, max_length=256)
    platform: str = Field(min_length=2, max_length=32)
    push_token: str = Field(min_length=16, max_length=4096)
    push_enabled: bool = True
    app_version: Optional[str] = Field(default=None, max_length=64)


class NotificationPreferencesRequest(StrictRequestModel):
    notifications_enabled: bool = True
    push_enabled: bool = True
    daily_reminder_enabled: bool = False
    daily_reminder_hour: int = Field(default=20, ge=0, le=23)
    daily_reminder_minute: int = Field(default=0, ge=0, le=59)
    timezone: str = Field(default="UTC", max_length=80)


class NotificationPreferencesResponse(BaseModel):
    notifications_enabled: bool
    push_enabled: bool
    daily_reminder_enabled: bool
    daily_reminder_hour: int
    daily_reminder_minute: int
    timezone: str


class NotificationTriggerRequest(StrictRequestModel):
    event_type: str = Field(min_length=2, max_length=64)
    title: str = Field(min_length=1, max_length=160)
    body: str = Field(min_length=1, max_length=4000)
    data: dict = Field(default_factory=dict)


class UploadValidationResponse(BaseModel):
    filename: str
    content_type: str
    size_bytes: int
    accepted: bool
    scan_status: str


class MediaUploadResponse(BaseModel):
    media_type: str
    filename: str
    content_type: str
    size_bytes: int
    bucket: str
    storage_path: str
    public_url: str


class NotificationTriggerResponse(BaseModel):
    event_type: str
    attempted: int
    sent: int
    failed: int


class NotificationHealthResponse(BaseModel):
    generated_at: str
    firebase_configured: bool
    notifications_enabled: bool
    push_enabled: bool
    active_devices: int
    stale_devices: int
    recent_sent: int
    recent_failed: int


class NotificationReadinessCheck(BaseModel):
    name: str
    status: str
    detail: str


class NotificationReadinessResponse(BaseModel):
    generated_at: str
    overall_status: str
    checks: List[NotificationReadinessCheck]
    total_devices: int
    active_devices: int
    stale_devices: int
    recent_sent: int
    recent_failed: int
