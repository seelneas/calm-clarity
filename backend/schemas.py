from pydantic import BaseModel, EmailStr, Field
from typing import Optional, List

class UserBase(BaseModel):
    email: EmailStr
    name: Optional[str] = None
    google_calendar_connected: int = 0
    apple_health_connected: int = 0

class UserCreate(UserBase):
    password: str

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class UserOut(UserBase):
    id: int

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str
    user: UserOut

class SocialAuth(BaseModel):
    token: str
    name: Optional[str] = None
    email: Optional[str] = None
    provider: str # 'google' or 'apple'


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ForgotPasswordResponse(BaseModel):
    message: str
    reset_token: Optional[str] = None
    reset_link: Optional[str] = None
    delivery: Optional[str] = None


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str


class MessageResponse(BaseModel):
    message: str


class AdminAccessResponse(BaseModel):
    is_admin: bool
    email: EmailStr


class AdminUserSummaryResponse(BaseModel):
    generated_at: str
    total_users: int
    users_with_google_calendar: int
    users_with_apple_health: int
    users_active_last_7_days: int
    ai_requests_last_7_days: int
    ai_requests_today: int


class AdminUserListItem(BaseModel):
    id: int
    name: Optional[str] = None
    email: EmailStr
    is_active: bool
    google_calendar_connected: bool
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


class AIAnalyzeEntryRequest(BaseModel):
    transcript: str
    summary: str
    mood: str
    mood_confidence: Optional[float] = None
    tags: List[str] = []


class AIAnalyzeEntryResponse(BaseModel):
    ai_summary: str = Field(min_length=1)
    ai_action_items: List[str]
    ai_mood_explanation: str = Field(min_length=1)
    ai_followup_prompt: str = Field(min_length=1)
    safety_flag: bool = False
    crisis_resources: List[str] = []


class AIWeeklyEntryInput(BaseModel):
    timestamp: str
    summary: str
    mood: str
    tags: List[str] = []
    ai_summary: Optional[str] = None
    transcript: Optional[str] = None


class AIWeeklyInsightsRequest(BaseModel):
    timeframe_label: Optional[str] = None
    entries: List[AIWeeklyEntryInput]
    memory_candidates: List[AIWeeklyEntryInput] = []
    memory_snippets: List[str] = []


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


class GoogleCalendarAccessTokenRequest(BaseModel):
    access_token: str


class GoogleCalendarEventCreateRequest(BaseModel):
    access_token: str
    summary: str
    start_iso: str
    end_iso: str
    description: Optional[str] = None
    timezone: Optional[str] = "UTC"


class GoogleCalendarEventOut(BaseModel):
    id: str
    summary: str
    status: Optional[str] = None
    html_link: Optional[str] = None
    start_iso: Optional[str] = None
    end_iso: Optional[str] = None


class GoogleCalendarLocalChange(BaseModel):
    action: str
    client_event_id: Optional[str] = None
    external_event_id: Optional[str] = None
    summary: Optional[str] = None
    description: Optional[str] = None
    start_iso: Optional[str] = None
    end_iso: Optional[str] = None
    timezone: Optional[str] = "UTC"


class GoogleCalendarSyncRunRequest(BaseModel):
    access_token: str
    local_changes: List[GoogleCalendarLocalChange] = []


class GoogleCalendarSyncSettingsRequest(BaseModel):
    auto_sync_enabled: bool = True
    sync_interval_minutes: int = 5


class GoogleCalendarSyncStatusResponse(BaseModel):
    connected: bool
    auto_sync_enabled: bool
    sync_interval_minutes: int
    last_sync_at: Optional[str] = None
    last_error: Optional[str] = None
    pending_count: int


class GoogleCalendarSyncRunResponse(BaseModel):
    synced_at: str
    pulled_count: int
    pushed_count: int
    failed_count: int
    pending_count: int
    events: List[GoogleCalendarEventOut]


class GoogleCalendarEventsResponse(BaseModel):
    connected: bool
    events: List[GoogleCalendarEventOut]


class NotificationDeviceRegisterRequest(BaseModel):
    device_id: str
    platform: str
    push_token: str
    push_enabled: bool = True
    app_version: Optional[str] = None


class NotificationPreferencesRequest(BaseModel):
    notifications_enabled: bool = True
    push_enabled: bool = True
    daily_reminder_enabled: bool = False
    daily_reminder_hour: int = 20
    daily_reminder_minute: int = 0
    timezone: str = "UTC"


class NotificationPreferencesResponse(BaseModel):
    notifications_enabled: bool
    push_enabled: bool
    daily_reminder_enabled: bool
    daily_reminder_hour: int
    daily_reminder_minute: int
    timezone: str


class NotificationTriggerRequest(BaseModel):
    event_type: str
    title: str
    body: str
    data: dict = {}


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
