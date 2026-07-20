from typing import Generic, TypeVar

from pydantic import BaseModel, ConfigDict

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
