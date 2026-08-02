import uuid
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import ConfigDict
from sqlmodel import Field, Relationship, SQLModel


def new_checkin_token() -> str:
    """Token ประจำกิจกรรมที่ใช้ทำ QR สำหรับเช็กอินหน้างาน (เดาไม่ได้ ไม่ซ้ำ)."""
    return uuid.uuid4().hex


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


class OcrDecision(str, Enum):
    auto_approved = "auto_approved"   # OCR confident + matched -> approved by the system
    needs_review = "needs_review"     # unclear / no match -> left for staff
    flagged = "flagged"               # duplicate file -> never auto-approved


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


class StudentCreateWithAccount(StudentCreate):
    """สร้างข้อมูลนิสิตพร้อมบัญชีเข้าใช้งานในคำขอเดียว

    แก้ปัญหาไก่กับไข่ของนิสิตใหม่: เดิมต้องเพิ่มข้อมูลนิสิตที่หน้าหนึ่ง แล้วไป
    สร้างบัญชีอีกหน้าหนึ่งเพื่อผูกกัน ถ้าลืมขั้นที่สองก็ได้นิสิตที่ล็อกอินไม่ได้

    บัญชีที่สร้างให้ใช้รูปแบบเดียวกับ seed.py คือ username และรหัสผ่านเริ่มต้น
    เป็น "รหัสนิสิต" ทั้งคู่ — แต่ผู้ดูแลกำหนดเองได้ผ่าน username/password

    ดีฟอลต์เป็น False เพื่อไม่ให้ผู้เรียก `POST /students` เดิมได้บัญชีเพิ่มมา
    โดยไม่ได้ขอ — ฝั่งแอปเป็นคนส่ง create_user=true มาเอง (ช่องติ๊กถูกติ๊กไว้ให้แล้ว)
    """

    # extra="forbid" กันการยัดฟิลด์ที่ระบบเป็นเจ้าของ (id, hashed_password) และ
    # ทำให้พิมพ์ชื่อฟิลด์ผิดกลายเป็น 422 แทนที่จะถูกกลืนไปเงียบ ๆ
    model_config = ConfigDict(extra="forbid")

    create_user: bool = False
    # เว้นว่างได้ทั้งคู่ = ใช้รหัสนิสิตเป็นทั้งชื่อผู้ใช้และรหัสผ่านเริ่มต้น
    # มีผลเฉพาะเมื่อ create_user=True เท่านั้น
    username: Optional[str] = None
    password: Optional[str] = None


class StudentUpdate(SQLModel):
    student_id: Optional[str] = None
    full_name: Optional[str] = None
    faculty: Optional[str] = None
    major: Optional[str] = None
    year_level: Optional[int] = None
    status: Optional[StudentStatus] = None


class StudentRead(StudentBase):
    id: int


class StudentWithAccountRead(StudentRead):
    """ผลลัพธ์ของการสร้างนิสิต — แนบชื่อผู้ใช้ที่ระบบสร้างให้มาด้วย

    ผู้ดูแลจะได้บอกนิสิตได้ทันทีว่าล็อกอินด้วยชื่อผู้ใช้อะไร โดยไม่ต้องเดาว่า
    ระบบใช้ดีฟอลต์หรือค่าที่กรอกมา เป็น None เมื่อไม่ได้ขอสร้างบัญชี

    ไม่มีรหัสผ่านและ hash อยู่ในนี้โดยตั้งใจ
    """

    username: Optional[str] = None


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
    is_required: bool = False
    max_participants: int
    start_at: datetime
    location: str
    # hours granted to a participant when their evidence is approved (single source
    # of truth for hours_earned; students/staff never type hours_earned by hand).
    hours: float = 0
    subcategory_id: Optional[int] = Field(default=None, foreign_key="hoursubcategory.id")


class Activity(ActivityBase, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    # QR เช็กอินหน้างาน: ไม่อยู่ใน ActivityBase โดยตั้งใจ — สร้างเองเสมอ ตั้งค่าจาก
    # ภายนอกไม่ได้ (ไม่อยู่ใน ActivityCreate/Update) และไม่หลุดออกไปกับ ActivityRead
    # ที่นิสิตทุกคนเห็น ต้องขอผ่าน GET /activities/{id}/checkin-qr เท่านั้น
    checkin_token: str = Field(default_factory=new_checkin_token, unique=True, index=True)
    created_by: Optional[int] = Field(default=None, foreign_key="user.id")
    approval_status: ApprovalStatus = ApprovalStatus.pending
    approved_by: Optional[int] = Field(default=None, foreign_key="user.id")
    approved_at: Optional[datetime] = None

    participations: list["Participation"] = Relationship(back_populates="activity")


class ActivityCreate(ActivityBase):
    # subcategory_id is the single source of truth for hour-category classification;
    # required here (unlike the nullable table column) so every new activity is classified.
    subcategory_id: int
    hours: float = Field(gt=0)  # every activity must declare how many hours it grants
    # must be positive: a 0 capacity is meaningless and would divide-by-zero in the
    # dashboard's low-participation fill-rate calculation.
    max_participants: int = Field(gt=0)


class ActivityUpdate(SQLModel):
    name: Optional[str] = None
    activity_type: Optional[str] = None
    is_required: Optional[bool] = None
    max_participants: Optional[int] = Field(default=None, gt=0)
    start_at: Optional[datetime] = None
    location: Optional[str] = None
    hours: Optional[float] = Field(default=None, gt=0)
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


class ParticipationCreate(SQLModel):
    # extra="forbid" rejects any attempt to inject hours_earned / evidence_status;
    # those are system-controlled (hours come from activity.hours on approval).
    model_config = ConfigDict(extra="forbid")

    student_id: int
    activity_id: int
    check_in_time: Optional[datetime] = None


class ParticipationUpdate(SQLModel):
    # student_id / activity_id are intentionally absent: an existing participation
    # may not be re-pointed to another student/activity (delete + recreate instead).
    # hours_earned is intentionally absent: it is derived from activity.hours.
    model_config = ConfigDict(extra="forbid")

    check_in_time: Optional[datetime] = None
    evidence_status: Optional[EvidenceStatus] = None


class ParticipationRead(ParticipationBase):
    id: int
    activity_name: Optional[str] = None
    has_evidence: bool = False
    evidence_uploaded_at: Optional[datetime] = None
    # Latest Silver-layer OCR summary, folded in so the participants list does not
    # need an extra request per row.
    has_ocr: bool = False
    ocr_decision: Optional[OcrDecision] = None
    ocr_match_score: Optional[float] = None
    ocr_confidence: Optional[float] = None


# ---------- Raw file (Bronze layer metadata / data lineage) ----------
class RawFile(SQLModel, table=True):
    __tablename__ = "raw_file"

    id: Optional[int] = Field(default=None, primary_key=True)
    bucket: str
    object_key: str
    original_filename: str
    content_type: str
    size_bytes: int
    checksum: str = Field(index=True)  # SHA-256 hex digest (integrity + duplicate detection)
    source_system: str  # e.g. "student_upload", "staff_import"
    uploaded_by: Optional[int] = Field(default=None, foreign_key="user.id")
    ingested_at: datetime = Field(default_factory=datetime.utcnow)
    participation_id: Optional[int] = Field(
        default=None, foreign_key="participation.id", index=True
    )


class RawFileRead(SQLModel):
    id: int
    bucket: str
    object_key: str
    original_filename: str
    content_type: str
    size_bytes: int
    checksum: str
    source_system: str
    uploaded_by: Optional[int] = None
    ingested_at: datetime
    participation_id: Optional[int] = None


# ---------- Silver layer (OCR result of a Bronze evidence file) ----------
class SilverEvidenceOcr(SQLModel, table=True):
    __tablename__ = "silver_evidence_ocr"

    id: Optional[int] = Field(default=None, primary_key=True)
    raw_file_id: int = Field(foreign_key="raw_file.id", index=True)  # source Bronze file
    participation_id: Optional[int] = Field(
        default=None, foreign_key="participation.id", index=True
    )
    extracted_text: str = ""             # full text OCR read from the file
    ocr_confidence: float = 0.0          # average OCR confidence (0-1)
    match_score: float = 0.0             # how well the text matches the student/activity (0-1)
    decision: OcrDecision = OcrDecision.needs_review
    is_duplicate: bool = False           # checksum already used by an approved participation
    processed_at: datetime = Field(default_factory=datetime.utcnow)


class SilverEvidenceOcrRead(SQLModel):
    id: int
    raw_file_id: int
    participation_id: Optional[int] = None
    extracted_text: str
    ocr_confidence: float
    match_score: float
    decision: OcrDecision
    is_duplicate: bool
    processed_at: datetime


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


class UserUpdate(SQLModel):
    """แก้ไขบัญชีผู้ใช้ — เปลี่ยนได้แค่สิทธิ์กับรหัสผ่าน

    `student_id` ถูกตัดออกโดยตั้งใจ: การผูกบัญชีกับข้อมูลนิสิตเกิดขึ้นที่เดียว
    คือตอนสร้างนิสิตผ่าน `POST /students` เท่านั้น ไม่งั้นจะกลับไปมีบัญชีนิสิต
    ที่ผูกผิดคน/ไม่ผูกใครเลยได้อีก

    extra="forbid" เพื่อให้การส่ง student_id มาเด้ง 422 ไม่ใช่ถูกกลืนเงียบ ๆ
    แล้วผู้ดูแลเข้าใจผิดว่าเปลี่ยนสำเร็จ
    """

    model_config = ConfigDict(extra="forbid")

    role: Optional[UserRole] = None
    password: Optional[str] = None


class UserRead(UserBase):
    id: int
