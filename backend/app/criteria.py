"""แมปนิสิต → ชุดเกณฑ์ (criteria set)

รหัสนิสิตของ ม.ทักษิณ ขึ้นต้นด้วยปีที่เข้าศึกษาสองหลัก (พ.ศ. สองหลักท้าย) จึงถอด
รุ่นออกมาได้เองโดยไม่ต้องให้ใครกรอก — ตามที่ยืนยันไว้ใน `DB_Redesign_ActivityCriteria.md` §8

    ปีที่เข้า (พ.ศ.) = 2500 + รหัสนิสิต 2 ตัวแรก

**กติกาการเลือกชุดอยู่ในข้อมูล ไม่ได้อยู่ในโค้ดนี้** — แต่ละชุดเกณฑ์บอกเองว่าเริ่มใช้
กับรุ่นไหนผ่าน ``criteria_set.effective_from_cohort`` แล้วที่นี่เลือก *ชุดที่ค่านั้นสูงสุด
ที่ยังไม่เกินรุ่นของนิสิต* (ภายใน program_type เดียวกัน) เหมือนขั้นบันได::

    legacy-2566   : เริ่มรุ่น 0     ┐ รุ่น 2566 ตกขั้นนี้
    2567-regular  : เริ่มรุ่น 2567  ┘ รุ่น 2568/2569 ตกขั้นนี้

เพิ่มชุดของรุ่น 2570 ทีหลัง = เพิ่มแถวเดียว นิสิตรหัส 70 ขึ้นไปจะย้ายไปชุดใหม่เอง
โดยไม่ต้องแก้ไฟล์นี้ (ก่อนหน้านี้เป็น ``if cohort >= 2567`` ที่ต้องแก้โค้ดทุกรุ่น)

ฟังก์ชันที่นี่คืน ``None`` อย่างสงบเมื่อยังไม่มีแถวที่ตรง แทนที่จะระเบิด — นิสิตที่สร้าง
ก่อนมีชุดเกณฑ์จะได้ `criteria_set_id = NULL` แล้วค่อย backfill ทีหลังได้
"""

from __future__ import annotations

from typing import Optional

from sqlmodel import Session, select

from .models import CriteriaSet, ProgramType

# ปีรุ่นที่ชุดเกณฑ์ Talent/PLO เริ่มใช้ — ใช้ตอน **seed** เท่านั้น (ค่าเริ่มต้นของแถวที่
# สร้าง) ไม่ใช่ตรรกะการแมปอีกต่อไป ตัวแมปอ่านจาก effective_from_cohort ในฐานล้วน ๆ
CRITERIA_2567_FROM_COHORT = 2567

# code ของชุดเกณฑ์เก่า (แปลงมาจากโครง 5 หมวด/13 หมวดย่อยเดิม)
LEGACY_CRITERIA_CODE = "legacy-2566"


def cohort_from_student_id(student_id: str) -> Optional[int]:
    """ปีที่เข้าศึกษา (พ.ศ.) จากรหัสนิสิต — คืน None ถ้ารหัสไม่เข้ารูปแบบ

    รับทั้งรหัส 9 หลัก (รุ่นเก่า) และ 10 หลัก (ข้อมูลจริงปัจจุบัน) เพราะสองตัวแรก
    มีความหมายเดียวกันทั้งสองแบบ
    """
    code = (student_id or "").strip()
    if len(code) < 2 or not code[:2].isdigit():
        return None
    return 2500 + int(code[:2])


def resolve_criteria_set(
    session: Session,
    cohort: Optional[int],
    program_type: ProgramType = ProgramType.regular,
) -> Optional[CriteriaSet]:
    """ชุดเกณฑ์ที่รุ่นนี้ต้องใช้ — ชุดที่เริ่มใช้ "ล่าสุดแต่ยังไม่เกิน" รุ่นของนิสิต

    เรียงลำดับด้วย ``effective_from_cohort`` ก่อน แล้วค่อย ``id`` เพื่อให้ผลคงที่เมื่อมี
    สองชุดเริ่มรุ่นเดียวกัน (เฟส 2 จะห้ามกรณีนี้ตอนสร้าง แต่ข้อมูลเก่าที่หลุดมาก่อนหน้า
    ต้องไม่ทำให้นิสิตสลับชุดไปมาระหว่างการเรียกสองครั้ง)

    ชุดที่ปิดใช้งาน (``is_active = False``) ไม่ถูกเลือก — การปิดชุดคือวิธีเลิกใช้เกณฑ์
    ที่ยกเลิกไปแล้วโดยไม่ต้องลบทิ้งพร้อมประวัติ
    """
    if cohort is None:
        return None

    found = session.exec(
        select(CriteriaSet)
        .where(
            CriteriaSet.program_type == program_type,
            CriteriaSet.is_active == True,  # noqa: E712 — SQL boolean ไม่ใช่ `is`
            CriteriaSet.effective_from_cohort <= cohort,
        )
        .order_by(
            CriteriaSet.effective_from_cohort.desc(),
            CriteriaSet.id.desc(),
        )
    ).first()
    if found is not None:
        return found

    # ไม่มีชุดของกลุ่มหลักสูตรนั้นเลย (เช่น ต่อเนื่อง ที่ยังไม่ได้ทำชุดของตัวเอง) —
    # ตกมาที่เกณฑ์เก่าซึ่งเป็นชุดเดียวที่เคยใช้ร่วมกันทุกกลุ่ม ดีกว่าปล่อยเป็น NULL
    # แล้วทั้งระบบคำนวณความครบเกณฑ์ของคนนั้นไม่ได้เลย
    return session.exec(
        select(CriteriaSet).where(
            CriteriaSet.code == LEGACY_CRITERIA_CODE,
            CriteriaSet.is_active == True,  # noqa: E712 — SQL boolean ไม่ใช่ `is`
        )
    ).first()


def criteria_set_code_for(
    session: Session,
    cohort: Optional[int],
    program_type: ProgramType = ProgramType.regular,
) -> Optional[str]:
    """code ของชุดเกณฑ์ที่รุ่นนี้ต้องใช้ — None เมื่อไม่รู้รุ่น หรือยังไม่มีชุดไหนในฐาน."""
    found = resolve_criteria_set(session, cohort, program_type)
    return found.code if found else None


def resolve_criteria_set_id(
    session: Session,
    student_id: str,
    program_type: ProgramType = ProgramType.regular,
    cohort: Optional[int] = None,
) -> Optional[int]:
    """หา `criteria_set.id` ที่ตรงกับรหัสนิสิต/รุ่น — None ถ้ายังไม่มีชุดนั้นในระบบ."""
    found = resolve_criteria_set(
        session, cohort or cohort_from_student_id(student_id), program_type
    )
    return found.id if found else None
