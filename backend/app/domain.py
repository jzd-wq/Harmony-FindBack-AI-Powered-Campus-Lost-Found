from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field, ConfigDict


class ItemType(str, Enum):
    LOST = "lost"
    FOUND = "found"


class ItemStatus(str, Enum):
    ACTIVE = "active"
    MATCHED = "matched"
    RETURNED = "returned"
    CLOSED = "closed"


class ScopeMode(str, Enum):
    SAME_SCHOOL = "same_school"
    CROSS_SCHOOL = "cross_school"


class ItemCreate(BaseModel):
    model_config = ConfigDict(use_enum_values=True)

    publisher_id: str = "demo-student"
    user_school_id: str
    item_school_id: str
    campus_id: Optional[str] = None
    location: str
    item_type: ItemType
    title: str
    description: str = ""
    category: Optional[str] = None
    color: Optional[str] = None
    image_url: Optional[str] = None
    occurred_at: datetime
    scope_mode: ScopeMode = ScopeMode.SAME_SCHOOL
    hidden_feature: Optional[str] = None


class Item(ItemCreate):
    id: UUID = Field(default_factory=uuid4)
    status: ItemStatus = ItemStatus.ACTIVE
    ai_features: Dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class AIAnalysis(BaseModel):
    category: Optional[str] = None
    color: Optional[str] = None
    brand: Optional[str] = None
    model: Optional[str] = None
    visible_text: List[str] = Field(default_factory=list)
    sensitive_text: List[str] = Field(default_factory=list)
    features: List[str] = Field(default_factory=list)
    confidence: float = Field(default=0, ge=0, le=1)


class MatchCandidate(BaseModel):
    lost_item_id: UUID
    found_item_id: UUID
    final_score: float = Field(ge=0, le=1)
    score_breakdown: Dict[str, float]
    explanation: List[str]
    needs_ai_review: bool = False
    ai_score: Optional[float] = Field(default=None, ge=0, le=1)
    ai_reasons: List[str] = Field(default_factory=list)


class School(BaseModel):
    id: str
    name: str
    city: str
    campuses: list[str] = Field(default_factory=list)


class ChatThreadCreate(BaseModel):
    item_id: UUID
    participant_id: str = "demo-student"


class ChatThread(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    item_id: UUID
    participant_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class ChatMessageCreate(BaseModel):
    sender_id: str = "demo-student"
    body: str = Field(min_length=1, max_length=1000)


class ChatMessage(BaseModel):
    id: UUID = Field(default_factory=uuid4)
    chat_id: UUID
    item_id: UUID
    sender_id: str
    body: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
