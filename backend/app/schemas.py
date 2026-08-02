from datetime import datetime
from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    skip: int
    limit: int


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ParticipationRegister(BaseModel):
    model_config = ConfigDict(extra="forbid")

    activity_id: int


class ParticipationCheckin(BaseModel):
    """สิ่งที่นิสิตยิงมาหลังสแกน QR — มีแค่ token, ตัวตนมาจาก JWT เท่านั้น
    (extra="forbid" กันแนบ student_id มาเช็กอินแทนคนอื่น)"""

    model_config = ConfigDict(extra="forbid")

    token: str = Field(min_length=1)


class ActivityCheckinQr(BaseModel):
    """ข้อมูลสำหรับให้เจ้าหน้าที่สร้าง QR แสดงหน้างาน."""

    activity_id: int
    activity_name: str
    token: str
    qr_payload: str
    start_at: datetime
    checkin_opens_at: datetime
    checkin_closes_at: datetime


class HourSubcategorySummary(BaseModel):
    id: int
    name: str
    required_hours: float
    earned_hours: float
    completed: bool


class HourCategorySummary(BaseModel):
    id: int
    name: str
    required_hours: float
    earned_hours: float
    completed: bool
    subcategories: list[HourSubcategorySummary]


class HourSubcategoryRead(BaseModel):
    id: int
    name: str
    required_hours: float


class HourCategoryRead(BaseModel):
    id: int
    name: str
    required_hours: float
    subcategories: list[HourSubcategoryRead]
