from datetime import datetime
from typing import Generic, Optional, TypeVar

from pydantic import BaseModel, ConfigDict, Field

from app.models import CountingRule, ProgramType

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


class ActivityImportRowError(BaseModel):
    """แถวที่นำเข้าไม่ได้ — เลขแถวคือเลขแถวจริงในไฟล์ ผู้ใช้จะได้เปิดไปแก้ถูกบรรทัด"""

    row: int
    message: str


class ActivityImportCreated(BaseModel):
    row: int
    id: int
    name: str


class ActivityImportResult(BaseModel):
    """สรุปผลการนำเข้า: สำเร็จกี่แถว ผิดกี่แถว พร้อมเหตุผลรายแถว

    แถวที่ผ่านถูกบันทึกจริงแม้แถวอื่นจะผิด — ไฟล์หนึ่งไฟล์ไม่ล้มทั้งไฟล์เพราะ
    แถวเดียวพิมพ์ผิด
    """

    total_rows: int
    created_count: int
    error_count: int
    created: list[ActivityImportCreated]
    errors: list[ActivityImportRowError]


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


class HourSubcategoryDetailRead(HourSubcategoryRead):
    """หมวดย่อยแบบรู้ว่าอยู่ใต้หมวดใหญ่ไหน — ใช้เป็นผลลัพธ์ของการสร้าง/แก้ไข

    [HourSubcategoryRead] ตัด `category_id` ออกโดยตั้งใจ เพราะมันซ้อนอยู่ใต้
    หมวดใหญ่ใน [HourCategoryRead] อยู่แล้ว แต่ผลลัพธ์ของ POST/PUT ยืนอยู่ลำพัง
    จึงต้องบอกพ่อแม่ของมันมาด้วย
    """

    category_id: int


class HourCategoryWrite(BaseModel):
    """ข้อมูลหมวดใหญ่ที่ admin ส่งมาสร้าง/แก้ไข (PUT = แทนที่ทั้งก้อน)"""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=200)
    # ต้องมากกว่า 0 เหมือน Activity.hours — หมวดที่ต้องการ 0 ชั่วโมงจะ "ครบเกณฑ์"
    # ตั้งแต่ยังไม่ทำอะไรเลย ซึ่งไม่มีความหมายในเกณฑ์ของ มทษ.
    required_hours: float = Field(gt=0)


class HourSubcategoryWrite(HourCategoryWrite):
    """ข้อมูลหมวดย่อย — เหมือนหมวดใหญ่แต่ต้องระบุว่าอยู่ใต้หมวดไหน

    ใส่ `category_id` ตอน PUT ได้ด้วย เท่ากับย้ายหมวดย่อยไปอยู่ใต้หมวดใหญ่อื่น
    """

    category_id: int


class CriteriaRequirementRead(BaseModel):
    """รายการเกณฑ์หนึ่งรายการที่กิจกรรมผูกถึงได้ (ตัวเลือกในฟอร์มกิจกรรม)"""

    id: int
    name: str
    required_hours: float
    is_mandatory: bool
    # หน่วยการเรียนรู้ที่รายการนี้สังกัด — ชุด 2567 จัดกลุ่มด้วย Talent จึงเอาหน่วย
    # มาแสดงเป็นคำอธิบายกำกับแทน
    learning_unit_name: Optional[str] = None
    # อยู่ในกลุ่มที่แชร์เป้าชั่วโมงไหม (เช่น Social รวม ≥ 16) — บอกผู้ใช้ว่ารายการนี้
    # ตรวจความครบที่ยอดรวมของกลุ่ม ไม่ใช่ที่ตัวมันเอง
    group_name: Optional[str] = None
    # id ของกลุ่มเดียวกัน — ฟอร์มแก้ไขต้องส่งค่าเดิมกลับใน PUT (แทนที่ทั้งแถว)
    # ไม่งั้นกดบันทึกเฉย ๆ รายการก็หลุดออกจากกลุ่ม
    group_id: Optional[int] = None
    # ฟิลด์ที่ PUT แทนที่ทั้งแถวเหมือนกัน — ฟอร์มแก้ไขต้องได้ค่าเดิมไปส่งกลับ ไม่งั้นแก้ชั่วโมง
    # รายการเดียวแล้ว "กฎพิเศษ" ของคู่ Social ในชุด 2567 หายไปเงียบ ๆ
    rule_note: Optional[str] = None
    organizer: Optional[str] = None
    min_activities: Optional[int] = None


class CriteriaGroupRead(BaseModel):
    """หัวข้อกลุ่มในฟอร์ม — Talent (ชุด 2567) หรือหน่วยการเรียนรู้ (ชุด legacy)"""

    key: str                      # "talent:1" / "unit:3" — ไม่ชนกันข้ามชนิด
    name: str
    subtitle: Optional[str] = None   # เช่น "PLO 1" หรือ "หน่วยที่ 3"
    requirements: list[CriteriaRequirementRead]


class CriteriaSetRead(BaseModel):
    """ชุดเกณฑ์พร้อมรายการเกณฑ์ที่จัดกลุ่มไว้แล้ว — ฟอร์มกิจกรรมเอาไปขึ้นตัวเลือกได้ตรง ๆ"""

    id: int
    code: str
    name: str
    academic_year: int
    program_type: str
    # ปีรุ่นแรกที่ชุดนี้เริ่มใช้ — หน้าจอเอาไปเขียนว่า "ใช้กับนิสิตรหัส XX ขึ้นไป"
    effective_from_cohort: int
    total_required_hours: float
    counting_rule: str
    # True = เกณฑ์ทางการที่ seed ไว้ แก้ผ่าน API ไม่ได้ (403) หน้าจอจึงต้องปิดปุ่มแก้/ลบ
    # ตั้งแต่แรก ไม่ใช่ปล่อยให้กดแล้วค่อยเด้ง error
    is_system: bool
    # จัดกลุ่มด้วยอะไร: "talent" (ชุดที่มี Talent/PLO) หรือ "learning_unit" (ชุดเก่า)
    grouped_by: str
    # เตือนเมื่อผลรวมชั่วโมงของรายการเกณฑ์ไม่เท่ากับ total_required_hours (None = ตรงแล้ว)
    hours_warning: Optional[str] = None
    groups: list[CriteriaGroupRead]
    # กลุ่มแชร์เป้าทั้งหมดของชุด รวมกลุ่มที่ยังไม่มีสมาชิก — ไม่มีรายการนี้ ฟอร์มจะผูก
    # รายการแรกเข้ากลุ่มที่เพิ่งสร้างไม่ได้ เพราะกลุ่มนั้นยังไม่โผล่ใน `groups` เลย
    requirement_groups: list["RequirementGroupRead"] = []

# ---------- เขียนชุดเกณฑ์ (เฟส 2: admin สร้าง/แก้ชุดของรุ่นอนาคตเองได้) ----------

class CriteriaSetWrite(BaseModel):
    """ข้อมูลชุดเกณฑ์ที่ผู้ดูแลกรอก — ใช้ทั้ง POST และ PUT (PUT = แทนที่ทั้งชุด)"""

    model_config = ConfigDict(extra="forbid")

    # กุญแจธรรมชาติที่ทั้งระบบใช้อ้างถึงชุด (seed_criteria.py ก็ค้นด้วย code)
    code: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=200)
    academic_year: int = Field(ge=2500, le=2700, description="ปีหลักสูตร (พ.ศ.)")
    program_type: ProgramType = ProgramType.regular
    # ปีรุ่นแรกที่ชุดนี้เริ่มใช้ — 0 = ครอบทุกรุ่นที่ยังไม่มีชุดของตัวเอง
    effective_from_cohort: int = Field(ge=0, le=2700)
    total_required_hours: float = Field(gt=0)
    counting_rule: CountingRule = CountingRule.min_per_requirement
    is_active: bool = True


class TalentWrite(BaseModel):
    """กลุ่ม Talent/PLO ภายในชุดเกณฑ์"""

    model_config = ConfigDict(extra="forbid")

    code: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=200)
    plo: Optional[str] = Field(default=None, max_length=64)
    sort_order: int = 0


class RequirementGroupWrite(BaseModel):
    """กลุ่มรายการเกณฑ์ที่ใช้เป้าชั่วโมงร่วมกัน (เช่น Social รวม >= 16)"""

    model_config = ConfigDict(extra="forbid")

    code: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=200)
    required_hours: float = Field(gt=0)
    rule_note: Optional[str] = None


class RequirementWrite(BaseModel):
    """รายการเกณฑ์หนึ่งรายการในชุด"""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=300)
    learning_unit_id: int
    talent_id: Optional[int] = None
    group_id: Optional[int] = None
    is_mandatory: bool = False
    required_hours: float = Field(default=0, ge=0)
    min_activities: Optional[int] = Field(default=None, ge=1)
    rule_note: Optional[str] = None
    organizer: Optional[str] = None


class LearningUnitRead(BaseModel):
    """หน่วยการเรียนรู้ 5 หน่วย — taxonomy คงที่ ใช้ร่วมกันทุกชุดเกณฑ์ (อ่านอย่างเดียว)"""

    id: int
    code: str
    name: str


class TalentRead(BaseModel):
    id: int
    criteria_set_id: int
    code: str
    name: str
    plo: Optional[str] = None
    sort_order: int


class RequirementGroupRead(BaseModel):
    id: int
    criteria_set_id: int
    code: str
    name: str
    required_hours: float
    rule_note: Optional[str] = None


# CriteriaSetRead อ้างถึง RequirementGroupRead ก่อนประกาศ — resolve forward ref ตรงนี้
CriteriaSetRead.model_rebuild()


class RequirementRead(BaseModel):
    id: int
    criteria_set_id: int
    name: str
    learning_unit_id: int
    talent_id: Optional[int] = None
    group_id: Optional[int] = None
    is_mandatory: bool
    required_hours: float
    min_activities: Optional[int] = None
    rule_note: Optional[str] = None
    organizer: Optional[str] = None


class CriteriaSetDetailRead(BaseModel):
    """ชุดเกณฑ์แบบแบน ๆ (ไม่จัดกลุ่ม) — คำตอบของ endpoint ที่เขียนข้อมูล

    ต่างจาก :class:`CriteriaSetRead` ที่จัดกลุ่มมาให้ฟอร์มกิจกรรมใช้ ที่นี่คืนค่าที่
    "เพิ่งบันทึกลงไปจริง" ตรง ๆ ผู้ดูแลจึงตรวจได้ว่าระบบเก็บอะไรไว้
    """

    id: int
    code: str
    name: str
    academic_year: int
    program_type: str
    effective_from_cohort: int
    total_required_hours: float
    counting_rule: str
    is_active: bool
    is_system: bool
    # เตือนเมื่อผลรวมชั่วโมงของรายการเกณฑ์ไม่เท่ากับ total_required_hours
    # ไม่ใช่ error เพราะระหว่างสร้างชุดใหม่ยอดย่อมยังไม่ครบจนกว่าจะใส่รายการจบ
    hours_warning: Optional[str] = None
