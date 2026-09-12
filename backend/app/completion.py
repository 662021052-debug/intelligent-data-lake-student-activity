"""ความครบเกณฑ์ของนิสิต — สรุปจากแถว ``gold_student_hours`` (นิสิต × รายการที่ตรวจความครบ)

แดชบอร์ด อีเมลกลุ่มเสี่ยง และสคริปต์ตรวจความถูกต้องใช้กติกาชุดเดียวกันจากที่นี่ รายชื่อ
"ผ่าน/เสี่ยง" ของทุกหน้าจึงตรงกันเสมอ (เดิมแดชบอร์ดตัดสินจากชั่วโมงรวม ≥ 60 ซึ่งไม่ดู
ว่าครบรายการไหน — ได้ 60 จากกิจกรรมรายการเดียวก็นับว่าผ่าน)

- **ครบเกณฑ์** = ทุกรายการครบเป้าของรายการนั้น (บังคับครบทุกตัว ∧ เลือกครบทุกรายการ ∧
  กลุ่มครบยอดรวม) — ความครบรายรายการคำนวณใน gold view แล้ว
- **ความคืบหน้า** = ชั่วโมงที่นับเข้าเกณฑ์ ÷ เป้ารวม โดยชั่วโมงเกินเป้าของรายการหนึ่ง
  ไม่ไปชดเชยรายการอื่น (ตัดที่เป้าของแต่ละรายการ) — 100% จึงเท่ากับครบเกณฑ์พอดี
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Optional


@dataclass(frozen=True)
class ItemProgress:
    key: int
    name: str
    earned_hours: float
    required_hours: float

    @property
    def completed(self) -> bool:
        return self.earned_hours >= self.required_hours

    @property
    def counted_hours(self) -> float:
        return min(self.earned_hours, self.required_hours)

    @property
    def missing_hours(self) -> float:
        return max(self.required_hours - self.earned_hours, 0.0)


@dataclass
class StudentProgress:
    items: list[ItemProgress] = field(default_factory=list)

    @property
    def required_hours(self) -> float:
        return sum(i.required_hours for i in self.items)

    @property
    def counted_hours(self) -> float:
        return sum(i.counted_hours for i in self.items)

    @property
    def missing_hours(self) -> float:
        return max(self.required_hours - self.counted_hours, 0.0)

    @property
    def completed(self) -> bool:
        # ไม่มีรายการเลย = ยังไม่มีเกณฑ์ให้วัด — ไม่นับว่าผ่าน
        return bool(self.items) and all(i.completed for i in self.items)

    @property
    def percent(self) -> float:
        required = self.required_hours
        return (self.counted_hours / required * 100) if required > 0 else 0.0

    @property
    def gaps(self) -> list[ItemProgress]:
        return [i for i in self.items if not i.completed]


def progress_by_student(
    rows: Iterable[tuple[int, int, str, float, Optional[float]]],
) -> dict[int, StudentProgress]:
    """แถว (student_key, item_key, item_name, required_hours, earned_hours) → ความคืบหน้ารายคน

    ลำดับรายการตามลำดับแถวที่ส่งมา (ผู้เรียกเรียงตาม item_key เอง)
    """
    result: dict[int, StudentProgress] = {}
    for student_key, item_key, name, required, earned in rows:
        result.setdefault(student_key, StudentProgress()).items.append(
            ItemProgress(item_key, str(name), float(earned or 0), float(required or 0))
        )
    return result
