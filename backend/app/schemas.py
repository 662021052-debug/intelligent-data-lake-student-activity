from datetime import datetime
from typing import Generic, Optional, TypeVar

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
    total_required_hours: float
    counting_rule: str
    # จัดกลุ่มด้วยอะไร: "talent" (ชุดที่มี Talent/PLO) หรือ "learning_unit" (ชุดเก่า)
    grouped_by: str
    groups: list[CriteriaGroupRead]
