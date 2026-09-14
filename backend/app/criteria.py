"""แมปนิสิต → ชุดเกณฑ์ (criteria set)

รหัสนิสิตของ ม.ทักษิณ ขึ้นต้นด้วยปีที่เข้าศึกษาสองหลัก (พ.ศ. สองหลักท้าย) จึงถอด
รุ่นออกมาได้เองโดยไม่ต้องให้ใครกรอก — ตามที่ยืนยันไว้ใน `DB_Redesign_ActivityCriteria.md` §8

    ปีที่เข้า (พ.ศ.) = 2500 + รหัสนิสิต 2 ตัวแรก
    เข้า ≥ 2567 → ชุดเกณฑ์ "2567" ของกลุ่มหลักสูตรนั้น
    เข้า ≤ 2566 → ชุดเกณฑ์เก่า (legacy)

ตัวชุดเกณฑ์เองถูก seed ในเฟสถัดไป ฟังก์ชันที่นี่จึงคืน `None` อย่างสงบเมื่อยังไม่มี
แถวที่ตรง แทนที่จะระเบิด — นิสิตที่สร้างก่อนมีชุดเกณฑ์จะได้ `criteria_set_id = NULL`
แล้วค่อย backfill ทีหลังได้
"""

from __future__ import annotations

from datetime import date
from typing import Optional

from sqlmodel import Session, select

from .models import CriteriaSet, ProgramType

# ปีหลักสูตรแรกที่ใช้โครงเกณฑ์ Talent/PLO — รุ่นก่อนหน้านี้ยังใช้เกณฑ์เก่า
CRITERIA_2567_FROM_COHORT = 2567

# code ของชุดเกณฑ์เก่า (แปลงมาจากโครง 5 หมวด/13 หมวดย่อยเดิม)
LEGACY_CRITERIA_CODE = "legacy-2566"

# ปีการศึกษาเริ่มเดือนมิถุนายน — ตรงกับที่ gold views ใช้ตัดปีการศึกษา (app/gold.py)
ACADEMIC_YEAR_START_MONTH = 6


def cohort_from_student_id(student_id: str) -> Optional[int]:
    """ปีที่เข้าศึกษา (พ.ศ.) จากรหัสนิสิต — คืน None ถ้ารหัสไม่เข้ารูปแบบ

    รับทั้งรหัส 9 หลัก (รุ่นเก่า) และ 10 หลัก (ข้อมูลจริงปัจจุบัน) เพราะสองตัวแรก
    มีความหมายเดียวกันทั้งสองแบบ
    """
    code = (student_id or "").strip()
    if len(code) < 2 or not code[:2].isdigit():
        return None
    return 2500 + int(code[:2])


def academic_year_of(day: date) -> int:
    """ปีการศึกษา (พ.ศ.) ที่วันนั้นอยู่ — ม.ค.–พ.ค. ยังเป็นปีการศึกษาที่เริ่มเมื่อ มิ.ย. ปีก่อน."""
    year = day.year + 543
    return year if day.month >= ACADEMIC_YEAR_START_MONTH else year - 1


def year_level_for(cohort: Optional[int], academic_year: int) -> Optional[int]:
    """ชั้นปีของรุ่นนี้ในปีการศึกษาที่ให้มา — None ถ้าไม่รู้รุ่น

    ไม่ต่ำกว่า 1 เสมอ: รุ่นที่ปีเข้ามากกว่าปีการศึกษาปัจจุบัน (รับล่วงหน้า/นาฬิกาเครื่องเพี้ยน)
    ก็ยังเป็นนิสิตปี 1 ไม่ใช่ปี 0 หรือติดลบ ส่วนด้านบนไม่ตัด เพราะนิสิตเรียนเกิน 4 ปีมีจริง
    """
    if cohort is None:
        return None
    return max(1, academic_year - cohort + 1)


def criteria_set_code_for(cohort: Optional[int], program_type: ProgramType) -> Optional[str]:
    """code ของชุดเกณฑ์ที่รุ่นนี้ต้องใช้ — None เมื่อไม่รู้ว่าเข้าปีไหน."""
    if cohort is None:
        return None
    if cohort >= CRITERIA_2567_FROM_COHORT:
        return f"{CRITERIA_2567_FROM_COHORT}-{program_type.value}"
    return LEGACY_CRITERIA_CODE


def resolve_criteria_set_id(
    session: Session,
    student_id: str,
    program_type: ProgramType = ProgramType.regular,
    cohort: Optional[int] = None,
) -> Optional[int]:
    """หา `criteria_set.id` ที่ตรงกับรหัสนิสิต/รุ่น — None ถ้ายังไม่มีชุดนั้นในระบบ."""
    code = criteria_set_code_for(cohort or cohort_from_student_id(student_id), program_type)
    if code is None:
        return None
    found = session.exec(select(CriteriaSet).where(CriteriaSet.code == code)).first()
    return found.id if found else None
