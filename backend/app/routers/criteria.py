"""ชุดเกณฑ์ + รายการเกณฑ์ — อ่านได้ทุก role · เขียนได้เฉพาะ admin

**อ่าน** (`GET`) จัดกลุ่มมาให้พร้อมใช้ เพราะสองชุดเกณฑ์จัดกลุ่มคนละแบบและ UI ไม่ควร
ต้องรู้กติกานี้เอง:

* ชุดที่มี Talent (2567): Talent/PLO → รายการเกณฑ์
* ชุด legacy: หน่วยการเรียนรู้ → รายการเกณฑ์

**เขียน** (`POST/PUT/DELETE`) มีไว้ให้ผู้ดูแลเตรียมชุดเกณฑ์ของรุ่นอนาคตเอง โดยไม่ต้อง
แก้โค้ดหรือรัน seed ใหม่ — ระบบจะแมปนิสิตรุ่นนั้นเข้าชุดใหม่ให้เองผ่าน
``effective_from_cohort`` (ดู ``app/criteria.py``)

กฎกันพลาดที่บังคับไว้ที่นี่ เพราะพลาดแต่ละอย่างมีราคาแพงและตามแก้ยาก:

1. **เนื้อหาในชุด (Talent / กลุ่มแชร์เป้า / รายการเกณฑ์) แก้ได้ทุกชุด รวมชุดทางการ** —
   ผู้ดูแลต้องปรับเกณฑ์ 2567 ได้เหมือนเกณฑ์เดิม และ ``seed_criteria.py`` สร้างชุดเฉพาะตอน
   ยังไม่มีในฐาน จึงไม่เขียนทับสิ่งที่แก้ไว้ตอนบูต · แต่ **ตัวชุดทางการ (`is_system`)
   แก้ข้อมูลระดับชุด/ลบไม่ได้** — ปีรุ่นที่เริ่มใช้คือขั้นบันไดที่นิสิตทั้งรุ่นแมปอยู่ ลบหรือ
   ขยับทีเดียวกระทบคนนับพัน
2. **ลบชุดที่มีนิสิตผูกอยู่ไม่ได้** — ลบแล้วคนกลุ่มนั้นจะไม่มีเกณฑ์ให้วัดเลย
3. **``effective_from_cohort`` ห้ามซ้ำใน ``program_type`` เดียวกัน** — ซ้ำเมื่อไหร่
   บันไดการแมปมีสองขั้นที่ความสูงเท่ากัน ผลลัพธ์จึงขึ้นกับลำดับ id ซึ่งไม่ใช่เจตนาของใคร
4. **เตือน (ไม่ห้าม) เมื่อผลรวมชั่วโมงไม่เท่า ``total_required_hours``** — ระหว่างสร้าง
   ชุดใหม่ยอดย่อมยังไม่ครบจนกว่าจะใส่รายการจบ ห้ามตรงนี้เท่ากับสร้างชุดใหม่ไม่ได้เลย
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, func, select

from app.auth import get_current_user, require_admin
from app.database import get_session
from app.models import (
    ActivityRequirement,
    CriteriaSet,
    LearningUnit,
    ProgramType,
    Requirement,
    RequirementGroup,
    Student,
    Talent,
)
from app.schemas import (
    CriteriaGroupRead,
    LearningUnitRead,
    CriteriaRequirementRead,
    CriteriaSetDetailRead,
    CriteriaSetRead,
    CriteriaSetWrite,
    RequirementGroupRead,
    RequirementGroupWrite,
    RequirementRead,
    RequirementWrite,
    TalentRead,
    TalentWrite,
)

router = APIRouter(
    prefix="/criteria-sets", tags=["criteria"], dependencies=[Depends(get_current_user)]
)

# Talent / กลุ่ม / รายการเกณฑ์ ถูกอ้างด้วย id ของตัวเองตอนแก้และลบ จึงแยก prefix
# ออกมาแทนที่จะซ้อนใต้ชุด (แบบเดียวกับ /hour-subcategories) — จะได้ไม่ต้องส่ง
# criteria_set_id ที่ไม่มีใครใช้มาใน path
talent_router = APIRouter(
    prefix="/talents", tags=["criteria"], dependencies=[Depends(get_current_user)]
)
requirement_group_router = APIRouter(
    prefix="/requirement-groups", tags=["criteria"], dependencies=[Depends(get_current_user)]
)
requirement_router = APIRouter(
    prefix="/requirements", tags=["criteria"], dependencies=[Depends(get_current_user)]
)
# หน่วยการเรียนรู้เป็น taxonomy คงที่ 5 หน่วยที่ทุกชุดเกณฑ์ใช้ร่วมกัน จึงมีแต่ทางอ่าน —
# ฟอร์มรายการเกณฑ์ต้องใช้เลือกว่าชั่วโมงของรายการนั้นนับเข้าหน่วยไหน
learning_unit_router = APIRouter(
    prefix="/learning-units", tags=["criteria"], dependencies=[Depends(get_current_user)]
)


@learning_unit_router.get("", response_model=list[LearningUnitRead])
def list_learning_units(session: Session = Depends(get_session)):
    units = session.exec(select(LearningUnit).order_by(LearningUnit.code)).all()
    return [LearningUnitRead(id=u.id, code=u.code, name=u.name) for u in units]


# --------------------------- ตัวช่วยกันพลาด ---------------------------
def _get_set(session: Session, criteria_set_id: int) -> CriteriaSet:
    criteria_set = session.get(CriteriaSet, criteria_set_id)
    if not criteria_set:
        raise HTTPException(status_code=404, detail="ไม่พบชุดเกณฑ์นี้")
    return criteria_set


def _reject_system_set(criteria_set: CriteriaSet) -> None:
    """ตัวชุดเกณฑ์ทางการแก้ข้อมูลระดับชุด/ลบไม่ได้ — ของข้างในชุดแก้ได้ตามปกติ

    403 ไม่ใช่ 409 เพราะเป็นเรื่อง "ไม่มีสิทธิ์แตะของชิ้นนี้" ไม่ใช่ "สถานะตอนนี้ชนกัน"
    ต่อให้ลองใหม่อีกกี่ครั้งก็ยังทำไม่ได้
    """
    if criteria_set.is_system:
        raise HTTPException(
            status_code=403,
            detail=f"ชุดเกณฑ์ {criteria_set.code} เป็นเกณฑ์ทางการของระบบ แก้ไขหรือลบไม่ได้",
        )


def _reject_duplicate_cohort(
    session: Session,
    *,
    program_type: ProgramType,
    effective_from_cohort: int,
    exclude_id: Optional[int],
) -> None:
    query = select(CriteriaSet).where(
        CriteriaSet.program_type == program_type,
        CriteriaSet.effective_from_cohort == effective_from_cohort,
    )
    if exclude_id is not None:
        query = query.where(CriteriaSet.id != exclude_id)
    clash = session.exec(query).first()
    if clash:
        raise HTTPException(
            status_code=400,
            detail=(
                f"ชุดเกณฑ์ {clash.code} ใช้ปีรุ่นเริ่มต้น {effective_from_cohort} "
                f"ของกลุ่มหลักสูตรนี้อยู่แล้ว — ปีรุ่นเริ่มต้นห้ามซ้ำกัน"
            ),
        )


def _hours_warning(session: Session, criteria_set: CriteriaSet) -> Optional[str]:
    """ผลรวมชั่วโมงของรายการเกณฑ์เทียบกับเป้าของชุด (None = ตรงกันแล้ว)

    รายการที่อยู่ในกลุ่มแชร์เป้าถูกนับเป็น "ก้อนของกลุ่ม" ครั้งเดียว ไม่ใช่บวกทีละตัว
    (กติกาเดียวกับ ``_spec_total_hours`` ใน seed_criteria.py และตัวคำนวณความครบ)
    """
    requirements = session.exec(
        select(Requirement).where(Requirement.criteria_set_id == criteria_set.id)
    ).all()
    groups = session.exec(
        select(RequirementGroup).where(RequirementGroup.criteria_set_id == criteria_set.id)
    ).all()

    used_group_ids = {r.group_id for r in requirements if r.group_id is not None}
    total = sum(r.required_hours for r in requirements if r.group_id is None)
    total += sum(g.required_hours for g in groups if g.id in used_group_ids)

    if abs(total - criteria_set.total_required_hours) < 1e-6:
        return None
    return (
        f"ผลรวมชั่วโมงของรายการเกณฑ์ ({total:g} ชม.) "
        f"ไม่เท่ากับชั่วโมงรวมของชุด ({criteria_set.total_required_hours:g} ชม.)"
    )


def _to_detail(session: Session, criteria_set: CriteriaSet) -> CriteriaSetDetailRead:
    return CriteriaSetDetailRead(
        id=criteria_set.id,
        code=criteria_set.code,
        name=criteria_set.name,
        academic_year=criteria_set.academic_year,
        program_type=criteria_set.program_type.value,
        effective_from_cohort=criteria_set.effective_from_cohort,
        total_required_hours=criteria_set.total_required_hours,
        counting_rule=criteria_set.counting_rule.value,
        is_active=criteria_set.is_active,
        is_system=criteria_set.is_system,
        hours_warning=_hours_warning(session, criteria_set),
    )


def _editable_set_of(session: Session, criteria_set_id: int) -> CriteriaSet:
    """ชุดที่แก้ข้อมูลระดับชุด/ลบได้ — 404 ถ้าไม่มี, 403 ถ้าเป็นชุดของระบบ"""
    criteria_set = _get_set(session, criteria_set_id)
    _reject_system_set(criteria_set)
    return criteria_set


def _talent(session: Session, talent_id: int) -> Talent:
    talent = session.get(Talent, talent_id)
    if not talent:
        raise HTTPException(status_code=404, detail="ไม่พบ Talent นี้")
    return talent


def _group(session: Session, group_id: int) -> RequirementGroup:
    group = session.get(RequirementGroup, group_id)
    if not group:
        raise HTTPException(status_code=404, detail="ไม่พบกลุ่มรายการเกณฑ์นี้")
    return group


def _requirement(session: Session, requirement_id: int) -> Requirement:
    requirement = session.get(Requirement, requirement_id)
    if not requirement:
        raise HTTPException(status_code=404, detail="ไม่พบรายการเกณฑ์นี้")
    return requirement


def _check_requirement_links(session: Session, payload: RequirementWrite, set_id: int) -> None:
    """ตรวจว่า learning_unit / talent / group ที่อ้างถึงมีจริงและอยู่ในชุดเดียวกัน

    ผูกข้ามชุดได้เมื่อไหร่ การจัดกลุ่มบนหน้าจอกับการคำนวณความครบจะเพี้ยนแบบเงียบ ๆ
    """
    if session.get(LearningUnit, payload.learning_unit_id) is None:
        raise HTTPException(status_code=400, detail="ไม่พบหน่วยการเรียนรู้ที่ระบุ")
    if payload.talent_id is not None:
        talent = _talent(session, payload.talent_id)
        if talent.criteria_set_id != set_id:
            raise HTTPException(status_code=400, detail="Talent ที่เลือกอยู่คนละชุดเกณฑ์")
    if payload.group_id is not None:
        group = _group(session, payload.group_id)
        if group.criteria_set_id != set_id:
            raise HTTPException(
                status_code=400, detail="กลุ่มรายการเกณฑ์ที่เลือกอยู่คนละชุดเกณฑ์"
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
        group_id=group.id if group else None,
        rule_note=requirement.rule_note,
        organizer=requirement.organizer,
        min_activities=requirement.min_activities,
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
                program_type=criteria_set.program_type.value,
                effective_from_cohort=criteria_set.effective_from_cohort,
                total_required_hours=criteria_set.total_required_hours,
                counting_rule=criteria_set.counting_rule.value,
                is_system=criteria_set.is_system,
                grouped_by="talent" if by_talent else "learning_unit",
                hours_warning=_hours_warning(session, criteria_set),
                groups=groups_read,
                requirement_groups=[
                    RequirementGroupRead(**g.model_dump())
                    for g in sorted(groups.values(), key=lambda g: g.id)
                    if g.criteria_set_id == criteria_set.id
                ],
            )
        )
    return result


# --------------------------- เขียนชุดเกณฑ์ (admin) ---------------------------
@router.post(
    "", response_model=CriteriaSetDetailRead, status_code=201,
    dependencies=[Depends(require_admin)],
)
def create_criteria_set(payload: CriteriaSetWrite, session: Session = Depends(get_session)):
    """สร้างชุดเกณฑ์ใหม่ (ของรุ่นอนาคต) — เป็นชุดของผู้ดูแลเสมอ ไม่ใช่ชุดระบบ"""
    code = payload.code.strip()
    if session.exec(select(CriteriaSet).where(CriteriaSet.code == code)).first():
        raise HTTPException(status_code=400, detail=f"มีชุดเกณฑ์รหัส {code} อยู่แล้ว")
    _reject_duplicate_cohort(
        session,
        program_type=payload.program_type,
        effective_from_cohort=payload.effective_from_cohort,
        exclude_id=None,
    )

    criteria_set = CriteriaSet(
        code=code,
        name=payload.name.strip(),
        academic_year=payload.academic_year,
        program_type=payload.program_type,
        effective_from_cohort=payload.effective_from_cohort,
        total_required_hours=payload.total_required_hours,
        counting_rule=payload.counting_rule,
        is_active=payload.is_active,
        # ชุดที่สร้างผ่าน API เป็นของผู้ดูแลเสมอ — ปล่อยให้ตั้ง is_system เองเมื่อไหร่
        # ก็เท่ากับเปิดช่องให้สร้างของที่ seed จะมาเขียนทับทีหลังโดยไม่มีใครตั้งใจ
        is_system=False,
    )
    session.add(criteria_set)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=400, detail="ข้อมูลซ้ำกับชุดเกณฑ์ที่มีอยู่แล้ว")
    session.refresh(criteria_set)
    return _to_detail(session, criteria_set)


@router.put(
    "/{criteria_set_id}", response_model=CriteriaSetDetailRead,
    dependencies=[Depends(require_admin)],
)
def update_criteria_set(
    criteria_set_id: int, payload: CriteriaSetWrite, session: Session = Depends(get_session)
):
    criteria_set = _editable_set_of(session, criteria_set_id)
    code = payload.code.strip()
    clash = session.exec(
        select(CriteriaSet).where(CriteriaSet.code == code, CriteriaSet.id != criteria_set_id)
    ).first()
    if clash:
        raise HTTPException(status_code=400, detail=f"มีชุดเกณฑ์รหัส {code} อยู่แล้ว")
    _reject_duplicate_cohort(
        session,
        program_type=payload.program_type,
        effective_from_cohort=payload.effective_from_cohort,
        exclude_id=criteria_set_id,
    )

    criteria_set.code = code
    criteria_set.name = payload.name.strip()
    criteria_set.academic_year = payload.academic_year
    criteria_set.program_type = payload.program_type
    criteria_set.effective_from_cohort = payload.effective_from_cohort
    criteria_set.total_required_hours = payload.total_required_hours
    criteria_set.counting_rule = payload.counting_rule
    criteria_set.is_active = payload.is_active
    session.add(criteria_set)
    session.commit()
    session.refresh(criteria_set)
    return _to_detail(session, criteria_set)


@router.delete("/{criteria_set_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_criteria_set(criteria_set_id: int, session: Session = Depends(get_session)):
    """ลบชุดเกณฑ์พร้อมของที่อยู่ข้างใน — เฉพาะชุดที่ยังไม่มีใครใช้

    Talent / กลุ่ม / รายการเกณฑ์ ถูกลบไปด้วยเพราะไม่มีความหมายเมื่อไม่มีชุดแม่
    แต่ถ้ามีนิสิตผูกอยู่ หรือมีกิจกรรมผูกกับรายการเกณฑ์ของชุดนี้ ต้องหยุด —
    ลบไปแล้วนิสิตจะไม่มีเกณฑ์ให้วัด และ FK ของ activity_requirement จะล้มกลางคัน
    """
    criteria_set = _editable_set_of(session, criteria_set_id)

    students = session.exec(
        select(func.count())
        .select_from(Student)
        .where(Student.criteria_set_id == criteria_set_id)
    ).one()
    if students:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: มีนิสิต {students} คนใช้ชุดเกณฑ์นี้อยู่",
        )

    linked = session.exec(
        select(func.count())
        .select_from(ActivityRequirement)
        .join(Requirement, Requirement.id == ActivityRequirement.requirement_id)
        .where(Requirement.criteria_set_id == criteria_set_id)
    ).one()
    if linked:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: มีกิจกรรมผูกกับรายการเกณฑ์ของชุดนี้อยู่ {linked} รายการ",
        )

    for requirement in session.exec(
        select(Requirement).where(Requirement.criteria_set_id == criteria_set_id)
    ).all():
        session.delete(requirement)
    # ลบรายการก่อน แล้วค่อยลบสิ่งที่รายการชี้ถึง ไม่งั้น FK ค้าง
    session.flush()
    for group in session.exec(
        select(RequirementGroup).where(RequirementGroup.criteria_set_id == criteria_set_id)
    ).all():
        session.delete(group)
    for talent in session.exec(
        select(Talent).where(Talent.criteria_set_id == criteria_set_id)
    ).all():
        session.delete(talent)
    session.delete(criteria_set)
    session.commit()
    return None


# --------------------------- Talent ---------------------------
@router.post(
    "/{criteria_set_id}/talents", response_model=TalentRead, status_code=201,
    dependencies=[Depends(require_admin)],
)
def create_talent(
    criteria_set_id: int, payload: TalentWrite, session: Session = Depends(get_session)
):
    _get_set(session, criteria_set_id)  # 404 ถ้าไม่มี · เพิ่มของในชุดทางการได้เหมือนชุดผู้ดูแล
    code = payload.code.strip()
    existing = session.exec(
        select(Talent).where(Talent.criteria_set_id == criteria_set_id, Talent.code == code)
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail=f"ชุดนี้มี Talent รหัส {code} อยู่แล้ว")

    talent = Talent(
        criteria_set_id=criteria_set_id,
        code=code,
        name=payload.name.strip(),
        plo=payload.plo,
        sort_order=payload.sort_order,
    )
    session.add(talent)
    session.commit()
    session.refresh(talent)
    return TalentRead(**talent.model_dump())


@talent_router.put(
    "/{talent_id}", response_model=TalentRead, dependencies=[Depends(require_admin)]
)
def update_talent(talent_id: int, payload: TalentWrite, session: Session = Depends(get_session)):
    talent = _talent(session, talent_id)
    _get_set(session, talent.criteria_set_id)

    code = payload.code.strip()
    clash = session.exec(
        select(Talent).where(
            Talent.criteria_set_id == talent.criteria_set_id,
            Talent.code == code,
            Talent.id != talent_id,
        )
    ).first()
    if clash:
        raise HTTPException(status_code=400, detail=f"ชุดนี้มี Talent รหัส {code} อยู่แล้ว")

    talent.code = code
    talent.name = payload.name.strip()
    talent.plo = payload.plo
    talent.sort_order = payload.sort_order
    session.add(talent)
    session.commit()
    session.refresh(talent)
    return TalentRead(**talent.model_dump())


@talent_router.delete("/{talent_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_talent(talent_id: int, session: Session = Depends(get_session)):
    talent = _talent(session, talent_id)
    _get_set(session, talent.criteria_set_id)

    used = session.exec(
        select(func.count()).select_from(Requirement).where(Requirement.talent_id == talent_id)
    ).one()
    if used:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: มีรายการเกณฑ์ {used} รายการอยู่ใน Talent นี้",
        )
    session.delete(talent)
    session.commit()
    return None


# --------------------------- กลุ่มรายการเกณฑ์ ---------------------------
@router.post(
    "/{criteria_set_id}/requirement-groups", response_model=RequirementGroupRead,
    status_code=201, dependencies=[Depends(require_admin)],
)
def create_requirement_group(
    criteria_set_id: int, payload: RequirementGroupWrite, session: Session = Depends(get_session)
):
    _get_set(session, criteria_set_id)  # 404 ถ้าไม่มี · เพิ่มของในชุดทางการได้เหมือนชุดผู้ดูแล
    code = payload.code.strip()
    existing = session.exec(
        select(RequirementGroup).where(
            RequirementGroup.criteria_set_id == criteria_set_id,
            RequirementGroup.code == code,
        )
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail=f"ชุดนี้มีกลุ่มรหัส {code} อยู่แล้ว")

    group = RequirementGroup(
        criteria_set_id=criteria_set_id,
        code=code,
        name=payload.name.strip(),
        required_hours=payload.required_hours,
        rule_note=payload.rule_note,
    )
    session.add(group)
    session.commit()
    session.refresh(group)
    return RequirementGroupRead(**group.model_dump())


@requirement_group_router.put(
    "/{group_id}", response_model=RequirementGroupRead, dependencies=[Depends(require_admin)]
)
def update_requirement_group(
    group_id: int, payload: RequirementGroupWrite, session: Session = Depends(get_session)
):
    group = _group(session, group_id)
    _get_set(session, group.criteria_set_id)

    group.code = payload.code.strip()
    group.name = payload.name.strip()
    group.required_hours = payload.required_hours
    group.rule_note = payload.rule_note
    session.add(group)
    session.commit()
    session.refresh(group)
    return RequirementGroupRead(**group.model_dump())


@requirement_group_router.delete(
    "/{group_id}", status_code=204, dependencies=[Depends(require_admin)]
)
def delete_requirement_group(group_id: int, session: Session = Depends(get_session)):
    group = _group(session, group_id)
    _get_set(session, group.criteria_set_id)

    used = session.exec(
        select(func.count()).select_from(Requirement).where(Requirement.group_id == group_id)
    ).one()
    if used:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: มีรายการเกณฑ์ {used} รายการใช้กลุ่มนี้อยู่",
        )
    session.delete(group)
    session.commit()
    return None


# --------------------------- รายการเกณฑ์ ---------------------------
@router.post(
    "/{criteria_set_id}/requirements", response_model=RequirementRead, status_code=201,
    dependencies=[Depends(require_admin)],
)
def create_requirement(
    criteria_set_id: int, payload: RequirementWrite, session: Session = Depends(get_session)
):
    _get_set(session, criteria_set_id)  # 404 ถ้าไม่มี · เพิ่มของในชุดทางการได้เหมือนชุดผู้ดูแล
    _check_requirement_links(session, payload, criteria_set_id)

    requirement = Requirement(
        criteria_set_id=criteria_set_id,
        name=payload.name.strip(),
        learning_unit_id=payload.learning_unit_id,
        talent_id=payload.talent_id,
        group_id=payload.group_id,
        is_mandatory=payload.is_mandatory,
        required_hours=payload.required_hours,
        min_activities=payload.min_activities,
        rule_note=payload.rule_note,
        organizer=payload.organizer,
    )
    session.add(requirement)
    session.commit()
    session.refresh(requirement)
    return RequirementRead(**requirement.model_dump())


@requirement_router.put(
    "/{requirement_id}", response_model=RequirementRead, dependencies=[Depends(require_admin)]
)
def update_requirement(
    requirement_id: int, payload: RequirementWrite, session: Session = Depends(get_session)
):
    requirement = _requirement(session, requirement_id)
    _get_set(session, requirement.criteria_set_id)
    _check_requirement_links(session, payload, requirement.criteria_set_id)

    requirement.name = payload.name.strip()
    requirement.learning_unit_id = payload.learning_unit_id
    requirement.talent_id = payload.talent_id
    requirement.group_id = payload.group_id
    requirement.is_mandatory = payload.is_mandatory
    requirement.required_hours = payload.required_hours
    requirement.min_activities = payload.min_activities
    requirement.rule_note = payload.rule_note
    requirement.organizer = payload.organizer
    session.add(requirement)
    session.commit()
    session.refresh(requirement)
    return RequirementRead(**requirement.model_dump())


@requirement_router.delete(
    "/{requirement_id}", status_code=204, dependencies=[Depends(require_admin)]
)
def delete_requirement(requirement_id: int, session: Session = Depends(get_session)):
    requirement = _requirement(session, requirement_id)
    _get_set(session, requirement.criteria_set_id)

    linked = session.exec(
        select(func.count())
        .select_from(ActivityRequirement)
        .where(ActivityRequirement.requirement_id == requirement_id)
    ).one()
    if linked:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: มีกิจกรรม {linked} รายการผูกกับรายการเกณฑ์นี้อยู่",
        )
    session.delete(requirement)
    session.commit()
    return None
