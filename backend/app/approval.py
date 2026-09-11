"""การอนุมัติการเข้าร่วม — กฎที่ทุกทางอนุมัติต้องใช้ร่วมกัน

การเข้าร่วมถูกอนุมัติได้หลายทาง (เจ้าหน้าที่กดอนุมัติ, OCR อนุมัติอัตโนมัติ, สคริปต์จำลอง
ข้อมูล) ถ้าแต่ละทางเขียนเอง ทางใดทางหนึ่งจะลืม snapshot แล้วประวัติของนิสิตจะเพี้ยน
ตามเกณฑ์ที่ถูกแก้ทีหลัง — กฎจึงอยู่ที่นี่ที่เดียว:

- ``hours_earned`` คัดจาก ``activity.hours`` เสมอ ไม่มีใครพิมพ์ชั่วโมงเอง (A2)
- snapshot หน่วยการเรียนรู้ + ชื่อรายการเกณฑ์ ณ เวลาอนุมัติ (DB_Redesign §3.7)
"""

from __future__ import annotations

from typing import Optional, Sequence

from sqlmodel import Session, select

from app.models import (
    Activity,
    ActivityRequirement,
    EvidenceStatus,
    Participation,
    Requirement,
    Student,
)


def requirement_snapshot(
    requirements: Sequence[Requirement], criteria_set_id: Optional[int]
) -> tuple[Optional[int], Optional[str]]:
    """(learning_unit_id, requirement_name) ที่กิจกรรมนี้นับให้นิสิตคนนี้

    กิจกรรมผูกได้หลายรายการเกณฑ์ และอาจข้ามชุดเกณฑ์ — เอาเฉพาะรายการในชุดของนิสิตก่อน
    (ไม่มีเลยค่อยใช้ทั้งหมด) ผูกหลายรายการได้ชื่อต่อกัน แต่หน่วยเก็บได้ค่าเดียว จึงเป็น None
    เมื่อรายการเหล่านั้นอยู่คนละหน่วย แทนที่จะเลือกหน่วยใดหน่วยหนึ่งให้ดูเหมือนแน่นอน
    กิจกรรมโครงเดิมที่ไม่ได้ผูกรายการเกณฑ์เลย (มีแต่ subcategory_id) ได้ (None, None)
    """
    if not requirements:
        return None, None
    own = [r for r in requirements if r.criteria_set_id == criteria_set_id] or list(requirements)
    own.sort(key=lambda r: r.id)
    units = {r.learning_unit_id for r in own}
    return (units.pop() if len(units) == 1 else None), " · ".join(r.name for r in own)


def apply_approval(session: Session, participation: Participation, activity: Activity) -> None:
    """ตั้งการเข้าร่วมเป็นอนุมัติ พร้อมชั่วโมงและ snapshot (ไม่ commit)."""
    requirements = session.exec(
        select(Requirement)
        .join(ActivityRequirement, ActivityRequirement.requirement_id == Requirement.id)
        .where(ActivityRequirement.activity_id == activity.id)
    ).all()
    student = session.get(Student, participation.student_id)
    participation.evidence_status = EvidenceStatus.approved
    participation.hours_earned = activity.hours
    participation.learning_unit_id, participation.requirement_name = requirement_snapshot(
        requirements, student.criteria_set_id if student else None
    )


def clear_approval(participation: Participation, status: EvidenceStatus) -> None:
    """ถอยกลับเป็น pending/rejected — ไม่ได้ชั่วโมง (E4) และไม่มี snapshot ที่ต้องจำ."""
    participation.evidence_status = status
    participation.hours_earned = 0
    participation.learning_unit_id = None
    participation.requirement_name = None
