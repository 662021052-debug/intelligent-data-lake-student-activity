"""ชุดเกณฑ์ + รายการเกณฑ์แบบอ่านอย่างเดียว — ให้ฟอร์มกิจกรรมเลือก requirement ได้

นิยามเกณฑ์ถูก seed เข้าฐาน (``seed_criteria.py``) ไม่ได้แก้ผ่าน UI จึงมีแต่ GET ที่นี่
โครงคำตอบจัดกลุ่มมาให้พร้อมใช้ เพราะสองชุดเกณฑ์จัดกลุ่มคนละแบบและ UI ไม่ควรต้องรู้กติกานี้เอง:

* ชุดที่มี Talent (2567): Talent/PLO → รายการเกณฑ์
* ชุด legacy: หน่วยการเรียนรู้ → รายการเกณฑ์
"""

from typing import Optional

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.auth import get_current_user
from app.database import get_session
from app.models import CriteriaSet, LearningUnit, Requirement, RequirementGroup, Talent
from app.schemas import CriteriaGroupRead, CriteriaRequirementRead, CriteriaSetRead

router = APIRouter(
    prefix="/criteria-sets", tags=["criteria"], dependencies=[Depends(get_current_user)]
)


def _requirement_read(
    requirement: Requirement,
    units: dict[int, LearningUnit],
    groups: dict[int, RequirementGroup],
) -> CriteriaRequirementRead:
    unit = units.get(requirement.learning_unit_id)
    group = groups.get(requirement.group_id) if requirement.group_id is not None else None
    return CriteriaRequirementRead(
        id=requirement.id,
        name=requirement.name,
        required_hours=requirement.required_hours,
        is_mandatory=requirement.is_mandatory,
        learning_unit_name=unit.name if unit else None,
        group_name=group.name if group else None,
    )


@router.get("", response_model=list[CriteriaSetRead])
def list_criteria_sets(
    include_inactive: bool = False,
    session: Session = Depends(get_session),
):
    """ชุดเกณฑ์ที่ใช้อยู่ พร้อมรายการเกณฑ์ที่จัดกลุ่มแล้ว (ปีล่าสุดขึ้นก่อน)"""
    query = select(CriteriaSet)
    if not include_inactive:
        query = query.where(CriteriaSet.is_active == True)  # noqa: E712 — SQL boolean, ไม่ใช่ `is`
    criteria_sets = session.exec(
        query.order_by(CriteriaSet.academic_year.desc(), CriteriaSet.code)
    ).all()
    if not criteria_sets:
        return []

    units = {u.id: u for u in session.exec(select(LearningUnit)).all()}
    groups = {g.id: g for g in session.exec(select(RequirementGroup)).all()}
    talents_by_set: dict[int, list[Talent]] = {}
    for talent in session.exec(select(Talent).order_by(Talent.sort_order, Talent.id)).all():
        talents_by_set.setdefault(talent.criteria_set_id, []).append(talent)

    set_ids = [cs.id for cs in criteria_sets]
    requirements_by_set: dict[int, list[Requirement]] = {}
    for requirement in session.exec(
        select(Requirement)
        .where(Requirement.criteria_set_id.in_(set_ids))
        .order_by(Requirement.learning_unit_id, Requirement.id)
    ).all():
        requirements_by_set.setdefault(requirement.criteria_set_id, []).append(requirement)

    result = []
    for criteria_set in criteria_sets:
        requirements = requirements_by_set.get(criteria_set.id, [])
        talents = talents_by_set.get(criteria_set.id, [])
        by_talent = bool(talents)

        if by_talent:
            # รายการที่ไม่ได้ผูก Talent จะไม่มีหัวข้อของตัวเอง — ต่อท้ายกลุ่มพิเศษไว้
            # ไม่งั้นมันจะหายไปจากฟอร์มและกิจกรรมผูกถึงไม่ได้เลย
            buckets: dict[Optional[int], list[Requirement]] = {}
            for requirement in requirements:
                buckets.setdefault(requirement.talent_id, []).append(requirement)
            groups_read = [
                CriteriaGroupRead(
                    key=f"talent:{talent.id}",
                    name=talent.name,
                    subtitle=talent.plo,
                    requirements=[
                        _requirement_read(r, units, groups) for r in buckets.get(talent.id, [])
                    ],
                )
                for talent in talents
                if buckets.get(talent.id)
            ]
            if buckets.get(None):
                groups_read.append(
                    CriteriaGroupRead(
                        key="talent:none",
                        name="ไม่ได้อยู่ใน Talent ใด",
                        requirements=[
                            _requirement_read(r, units, groups) for r in buckets[None]
                        ],
                    )
                )
        else:
            unit_buckets: dict[int, list[Requirement]] = {}
            for requirement in requirements:
                unit_buckets.setdefault(requirement.learning_unit_id, []).append(requirement)
            groups_read = [
                CriteriaGroupRead(
                    key=f"unit:{unit_id}",
                    name=units[unit_id].name if unit_id in units else f"หน่วยที่ {unit_id}",
                    subtitle=f"หน่วยที่ {units[unit_id].code}" if unit_id in units else None,
                    requirements=[
                        _requirement_read(r, units, groups) for r in unit_requirements
                    ],
                )
                for unit_id, unit_requirements in sorted(
                    unit_buckets.items(),
                    key=lambda item: units[item[0]].code if item[0] in units else str(item[0]),
                )
            ]

        result.append(
            CriteriaSetRead(
                id=criteria_set.id,
                code=criteria_set.code,
                name=criteria_set.name,
                academic_year=criteria_set.academic_year,
                total_required_hours=criteria_set.total_required_hours,
                counting_rule=criteria_set.counting_rule.value,
                grouped_by="talent" if by_talent else "learning_unit",
                groups=groups_read,
            )
        )
    return result
