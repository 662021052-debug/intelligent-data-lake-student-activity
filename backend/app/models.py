from datetime import datetime
from enum import Enum
from typing import Optional

from sqlmodel import Field, Relationship, SQLModel


class UserRole(str, Enum):
    student = "student"
    staff = "staff"
    admin = "admin"


class StudentStatus(str, Enum):
    active = "active"          # กำลังศึกษา
    inactive = "inactive"      # พ้นสภาพ


class EvidenceStatus(str, Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"


class ApprovalStatus(str, Enum):
    pending = "pending"
    approved = "approved"


# ---------- Student ----------
class StudentBase(SQLModel):
    student_id: str = Field(unique=True, index=True)
    full_name: str
    faculty: str
    major: str
    year_level: int
    status: StudentStatus = StudentStatus.active


class Student(StudentBase, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)

    participations: list["Participation"] = Relationship(back_populates="student")


class StudentCreate(StudentBase):
    pass


class StudentUpdate(SQLModel):
    student_id: Optional[str] = None
    full_name: Optional[str] = None
    faculty: Optional[str] = None
    major: Optional[str] = None
    year_level: Optional[int] = None
    status: Optional[StudentStatus] = None


class StudentRead(StudentBase):
    id: int


# ---------- Hour category / subcategory (เกณฑ์ชั่วโมงกิจกรรม) ----------
class HourCategory(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    required_hours: float

    subcategories: list["HourSubcategory"] = Relationship(back_populates="category")


class HourSubcategory(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    category_id: int = Field(foreign_key="hourcategory.id")
    name: str
    required_hours: float

    category: Optional[HourCategory] = Relationship(back_populates="subcategories")


# ---------- Activity ----------
class ActivityBase(SQLModel):
    name: str
    activity_type: str
    hour_category: str
    is_required: bool = False
    max_participants: int
    start_at: datetime
    location: str
    subcategory_id: Optional[int] = Field(default=None, foreign_key="hoursubcategory.id")


class Activity(ActivityBase, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    created_by: Optional[int] = Field(default=None, foreign_key="user.id")
    approval_status: ApprovalStatus = ApprovalStatus.pending
    approved_by: Optional[int] = Field(default=None, foreign_key="user.id")
    approved_at: Optional[datetime] = None

    participations: list["Participation"] = Relationship(back_populates="activity")


class ActivityCreate(ActivityBase):
    pass


class ActivityUpdate(SQLModel):
    name: Optional[str] = None
    activity_type: Optional[str] = None
    hour_category: Optional[str] = None
    is_required: Optional[bool] = None
    max_participants: Optional[int] = None
    start_at: Optional[datetime] = None
    location: Optional[str] = None
    subcategory_id: Optional[int] = None


class ActivityRead(ActivityBase):
    id: int
    created_by: Optional[int] = None
    approval_status: ApprovalStatus
    approved_by: Optional[int] = None
    approved_at: Optional[datetime] = None
    participant_count: int = 0


# ---------- Participation ----------
class ParticipationBase(SQLModel):
    student_id: int = Field(foreign_key="student.id", index=True)
    activity_id: int = Field(foreign_key="activity.id", index=True)
    check_in_time: Optional[datetime] = None
    hours_earned: float = 0
    evidence_status: EvidenceStatus = EvidenceStatus.pending


class Participation(ParticipationBase, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)

    student: Optional[Student] = Relationship(back_populates="participations")
    activity: Optional[Activity] = Relationship(back_populates="participations")


class ParticipationCreate(ParticipationBase):
    pass


class ParticipationUpdate(SQLModel):
    student_id: Optional[int] = None
    activity_id: Optional[int] = None
    check_in_time: Optional[datetime] = None
    hours_earned: Optional[float] = None
    evidence_status: Optional[EvidenceStatus] = None


class ParticipationRead(ParticipationBase):
    id: int


# ---------- User ----------
class UserBase(SQLModel):
    username: str = Field(unique=True, index=True)
    role: UserRole = UserRole.student
    student_id: Optional[int] = Field(default=None, foreign_key="student.id")


class User(UserBase, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    hashed_password: str


class UserCreate(UserBase):
    password: str


class UserRead(UserBase):
    id: int
