import uuid
from datetime import date, datetime
from enum import Enum
from typing import Optional

from pydantic import ConfigDict, model_validator
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


class ProgramType(str, Enum):
    """กลุ่มหลักสูตรของนิสิต — เกณฑ์ชั่วโมงต่างกัน (ปกติ 60 ชม. / ต่อเนื่อง 30 ชม.)."""

    regular = "regular"          # หลักสูตรปกติ 4 ปี
    continuing = "continuing"    # ต่อเนื่อง/ภาคพิเศษ 2 ปี


class ImportedCompletion(str, Enum):
    """สถานะ ผ่าน/ไม่ผ่าน เกณฑ์กิจกรรม ตามไฟล์รายชื่อนิสิตที่นำเข้า (ไม่ใช่ค่าที่ระบบคำนวณ)."""

    passed = "passed"    # "ผ่าน"
    failed = "failed"    # "ไม่ผ่าน"


class CountingRule(str, Enum):
    """วิธีนับว่านิสิต "ครบเกณฑ์" ของชุดเกณฑ์นั้น

    เดิมเป็น open item ที่ยังไม่ได้ข้อสรุปกับอาจารย์ จึงเก็บไว้ที่ระดับชุดเกณฑ์
    เพื่อให้ต่างปี/ต่างกลุ่มใช้กติกาต่างกันได้โดยไม่ต้องแก้โค้ด
    """

    total_per_unit = "total_per_unit"              # ดูยอดรวมของแต่ละหน่วยการเรียนรู้
    min_per_requirement = "min_per_requirement"    # ต้องได้ขั้นต่ำครบทุกรายการเกณฑ์


# ---------- ชุดเกณฑ์กิจกรรม (criteria versioning) ----------
class CriteriaSet(SQLModel, table=True):
    """หนึ่งชุดเกณฑ์ = ปีหลักสูตร × กลุ่มนิสิต (เช่น 2567 หลักสูตรปกติ 60 ชม.)

    แยก "นิยามเกณฑ์" ออกจาก "การเข้าร่วมจริง" เกณฑ์จึงเปลี่ยนรายปีได้โดยไม่กระทบ
    ประวัติของรุ่นก่อน — นิสิตแต่ละคนผูกกับชุดของตัวเองผ่าน `student.criteria_set_id`
    """

    __tablename__ = "criteria_set"

    id: Optional[int] = Field(default=None, primary_key=True)
    code: str = Field(unique=True, index=True)          # เช่น "2567-regular", "legacy-2566"
    academic_year: int                                   # ปีหลักสูตร (พ.ศ.)
    program_type: ProgramType = ProgramType.regular
    name: str
    total_required_hours: float
    counting_rule: CountingRule = CountingRule.min_per_requirement
    is_active: bool = True
    effective_from: Optional[date] = None
    effective_to: Optional[date] = None


class Talent(SQLModel, table=True):
    """กลุ่ม Talent/PLO ภายในชุดเกณฑ์ (โครง 2567) — ชุดเก่าไม่มีก็ได้."""

    id: Optional[int] = Field(default=None, primary_key=True)
    criteria_set_id: int = Field(foreign_key="criteria_set.id", index=True)
    code: str                                    # เช่น "glocal", "communication", "social"
    name: str
    plo: Optional[str] = None                    # เช่น "PLO 1"
    # ชื่อคอลัมน์เลี่ยงคำว่า order ซึ่งเป็นคำสงวนของ SQL
    sort_order: int = 0


class LearningUnit(SQLModel, table=True):
    """หน่วยการเรียนรู้ 5 หน่วย — taxonomy คงที่ ใช้ร่วมกันทุกชุดเกณฑ์."""

    __tablename__ = "learning_unit"

    id: Optional[int] = Field(default=None, primary_key=True)
    code: str = Field(unique=True, index=True)   # "1".."5"
    name: str


class RequirementGroup(SQLModel, table=True):
    """กลุ่มรายการเกณฑ์ที่ "ใช้เป้าชั่วโมงร่วมกัน" — ตรวจความครบที่ยอดรวมของกลุ่ม

    เช่น Social (PLO3) สองด้าน: เลือกด้านใดด้านหนึ่งครบ 16 ชม. หรือสองด้านรวมกัน ≥ 16 ก็ได้
    — เท่ากับ "ผลรวมของสมาชิก ≥ 16" (ด้านเดียวครบก็ทำให้ผลรวมครบอยู่แล้ว) รายการที่อยู่ในกลุ่ม
    จึงไม่ถูกตรวจทีละตัว required_hours ของสมาชิกเหลือไว้เป็นข้อมูลอ้างอิงเท่านั้น
    """

    __tablename__ = "requirement_group"

    id: Optional[int] = Field(default=None, primary_key=True)
    criteria_set_id: int = Field(foreign_key="criteria_set.id", index=True)
    code: str                                   # เช่น "social-16" — กุญแจธรรมชาติภายในชุดเกณฑ์
    name: str
    required_hours: float
    rule_note: Optional[str] = None


class Requirement(SQLModel, table=True):
    """รายการเกณฑ์ย่อยที่กิจกรรมผูกถึง — ตัวแทนของ HourSubcategory เดิม."""

    id: Optional[int] = Field(default=None, primary_key=True)
    criteria_set_id: int = Field(foreign_key="criteria_set.id", index=True)
    talent_id: Optional[int] = Field(default=None, foreign_key="talent.id", index=True)
    learning_unit_id: int = Field(foreign_key="learning_unit.id", index=True)
    # อยู่ในกลุ่มที่แชร์เป้าชั่วโมง = ตรวจที่ยอดรวมของกลุ่ม ไม่ใช่ที่รายการนี้ตัวเดียว
    group_id: Optional[int] = Field(default=None, foreign_key="requirement_group.id", index=True)
    name: str
    is_mandatory: bool = False
    required_hours: float = 0
    min_activities: Optional[int] = None
    # คำอธิบายกฎสำหรับคนอ่าน (กฎที่ตรวจอัตโนมัติอยู่ใน requirement_group)
    rule_note: Optional[str] = None
    organizer: Optional[str] = None


class ActivityRequirement(SQLModel, table=True):
    """ตารางเชื่อม กิจกรรม ↔ รายการเกณฑ์ (many-to-many)

    กิจกรรมหนึ่งงานนับให้ได้หลายรายการเกณฑ์ (และรายการเกณฑ์เดียวมีได้หลายกิจกรรม)
    ซึ่ง `activity.subcategory_id` เดิมที่เป็นค่าเดียวทำไม่ได้
    """

    __tablename__ = "activity_requirement"

    activity_id: int = Field(foreign_key="activity.id", primary_key=True)
    requirement_id: int = Field(foreign_key="requirement.id", primary_key=True)


# ---------- Student ----------
class StudentBase(SQLModel):
    student_id: str = Field(unique=True, index=True)
    full_name: str
    faculty: str
    major: str
    year_level: int
    status: StudentStatus = StudentStatus.active
    # ปีที่เข้าศึกษา (พ.ศ.) — เว้นว่างได้ ระบบถอดจากรหัสนิสิตให้เอง (ดู app/criteria.py)
    cohort: Optional[int] = None
    program_type: ProgramType = ProgramType.regular
    # ชุดเกณฑ์ที่นิสิตคนนี้ต้องทำให้ครบ — ระบบเลือกให้จาก cohort + program_type
    criteria_set_id: Optional[int] = Field(default=None, foreign_key="criteria_set.id", index=True)


class Student(StudentBase, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    # สถานะตามไฟล์ต้นทาง — ใช้สร้างการเข้าร่วมจำลองให้ผลออกมาตรงกับของจริง แล้วเทียบกับ
    # completion ที่ระบบคำนวณเอง อยู่ที่ตารางอย่างเดียว ไม่อยู่ใน StudentBase เพราะไม่ใช่ข้อมูล
    # ที่ผู้ดูแลกรอก/แก้ผ่าน API และถ้าโชว์คู่กับผลที่ระบบคำนวณจะสับสนว่าอันไหนจริง
    imported_completion: Optional[ImportedCompletion] = None

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
    cohort: Optional[int] = None
    program_type: Optional[ProgramType] = None
    criteria_set_id: Optional[int] = None


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
    # "ซ่อน" แทนการลบ สำหรับกิจกรรมที่มีคนเข้าร่วมไปแล้ว — ลบจริงจะทำให้ชั่วโมงที่
    # นิสิตได้ไปหายตามไปด้วย ตั้งค่าจากภายนอกไม่ได้ (ไม่อยู่ใน ActivityCreate/Update)
    # เปลี่ยนได้ทาง DELETE (ซ่อน) และ PATCH /unhide (เลิกซ่อน) เท่านั้น
    is_hidden: bool = Field(default=False, index=True)
    created_by: Optional[int] = Field(default=None, foreign_key="user.id")
    approval_status: ApprovalStatus = ApprovalStatus.pending
    approved_by: Optional[int] = Field(default=None, foreign_key="user.id")
    approved_at: Optional[datetime] = None

    participations: list["Participation"] = Relationship(back_populates="activity")


class ActivityCreate(ActivityBase):
    # การจัดหมวดของกิจกรรมมีสองทางระหว่างช่วงเปลี่ยนผ่าน: `requirement_ids` (ชุดเกณฑ์
    # ใหม่ ผูกได้หลายรายการ) และ `subcategory_id` (โครงหมวดเดิม) — ต้องมีอย่างน้อย
    # หนึ่งทางเสมอ ไม่งั้นกิจกรรมจะไม่นับชั่วโมงให้ใครเลย
    subcategory_id: Optional[int] = None
    requirement_ids: list[int] = Field(default_factory=list)
    hours: float = Field(gt=0)  # every activity must declare how many hours it grants
    # must be positive: a 0 capacity is meaningless and would divide-by-zero in the
    # dashboard's low-participation fill-rate calculation.
    max_participants: int = Field(gt=0)

    @model_validator(mode="after")
    def _require_classification(self) -> "ActivityCreate":
        if not self.requirement_ids and self.subcategory_id is None:
            raise ValueError("ต้องระบุ requirement_ids หรือ subcategory_id อย่างน้อยหนึ่งอย่าง")
        return self


class ActivityUpdate(SQLModel):
    name: Optional[str] = None
    activity_type: Optional[str] = None
    is_required: Optional[bool] = None
    max_participants: Optional[int] = Field(default=None, gt=0)
    start_at: Optional[datetime] = None
    location: Optional[str] = None
    hours: Optional[float] = Field(default=None, gt=0)
    subcategory_id: Optional[int] = None
    # ส่งมา = แทนที่รายการเกณฑ์ทั้งชุดของกิจกรรมนี้ · ไม่ส่ง = ไม่แตะของเดิม
    requirement_ids: Optional[list[int]] = None


class ActivityRead(ActivityBase):
    id: int
    created_by: Optional[int] = None
    approval_status: ApprovalStatus
    approved_by: Optional[int] = None
    approved_at: Optional[datetime] = None
    participant_count: int = 0
    # staff/admin ใช้ขึ้น badge "ซ่อนอยู่" — นิสิตไม่เคยเห็นแถวที่ซ่อนอยู่แล้ว
    is_hidden: bool = False
    requirement_ids: list[int] = Field(default_factory=list)


# ---------- Participation ----------
class ParticipationBase(SQLModel):
    student_id: int = Field(foreign_key="student.id", index=True)
    activity_id: int = Field(foreign_key="activity.id", index=True)
    check_in_time: Optional[datetime] = None
    hours_earned: float = 0
    evidence_status: EvidenceStatus = EvidenceStatus.pending
    # snapshot ณ เวลาอนุมัติ — เกณฑ์แก้ทีหลังแล้วประวัติต้องไม่เปลี่ยนตาม
    # (คู่กับ hours_earned ที่ snapshot ชั่วโมงไว้อยู่แล้ว)
    learning_unit_id: Optional[int] = Field(
        default=None, foreign_key="learning_unit.id", index=True
    )
    requirement_name: Optional[str] = None


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
