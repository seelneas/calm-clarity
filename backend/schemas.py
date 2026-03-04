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


class AIWeeklyInsightsRequest(BaseModel):
    timeframe_label: Optional[str] = None
    entries: List[AIWeeklyEntryInput]
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
