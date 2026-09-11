"""เฟส 2 ของการรื้อ DB: ใส่ "นิยามเกณฑ์" ลงฐานข้อมูล

สร้าง หน่วยการเรียนรู้ 5 หน่วย · ชุดเกณฑ์ ``legacy-2566`` (แปลงจาก hourcategory/
hoursubcategory เดิม) · ชุดเกณฑ์ ``2567-regular`` พร้อม Talent 3 กลุ่มและรายการเกณฑ์
ตาม ``docs/DB_Redesign_ActivityCriteria.md`` §9

แยกจาก ``seed.py`` เพราะคนละชนิดของข้อมูล: seed.py สร้าง *ข้อมูลเดโม* และข้ามทั้งไฟล์
ทันทีที่เจอบัญชีผู้ใช้สักคน — ซึ่งหลังรัน ``wipe_data.py`` ก็ยังมี staff/admin เหลืออยู่เสมอ
ไฟล์นี้สร้าง *นิยามเกณฑ์* ที่ต้องมีทุกฐาน ไม่ว่าจะมีข้อมูลจริงอยู่แล้วหรือไม่ จึงเขียนให้
รันซ้ำได้ (สร้างของที่ขาด · อัปเดตของที่ค่าเพี้ยนจากเอกสาร · ไม่แตะแถวที่คนเพิ่มเองทีหลัง)

รัน:
    python seed_criteria.py             # สร้าง/อัปเดตให้ตรงกับเอกสาร
    python seed_criteria.py --dry-run   # บอกว่าจะเปลี่ยนอะไร โดยไม่เขียนจริง
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from typing import Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlmodel import Session, select

from app.criteria import LEGACY_CRITERIA_CODE
from app.database import create_db_and_tables, engine
from app.models import (
    CountingRule,
    CriteriaSet,
    HourCategory,
    HourSubcategory,
    LearningUnit,
    ProgramType,
    Requirement,
    Student,
    Talent,
)

# ---------- หน่วยการเรียนรู้ (taxonomy คงที่ ใช้ร่วมกันทุกชุดเกณฑ์ — §3.3) ----------
LEARNING_UNITS: list[tuple[str, str]] = [
    ("1", "พัฒนาทักษะชีวิต"),
    ("2", "TSU รับใช้สังคม"),
    ("3", "ศิลปวัฒนธรรมอาเซียน"),
    ("4", "พัฒนาคุณธรรมและวินัย"),
    ("5", "ใฝ่เรียนรู้ตลอดชีวิต"),
]

# หมวดเดิมทั้ง 5 ชื่อตรงกับหน่วยการเรียนรู้อยู่แล้ว การแปลง legacy จึงเป็นการจับคู่ชื่อตรง ๆ
LEGACY_UNIT_BY_CATEGORY: dict[str, str] = {
    "พัฒนาทักษะชีวิต": "1",
    "TSU รับใช้สังคม": "2",
    "ศิลปวัฒนธรรมอาเซียน": "3",
    "พัฒนาคุณธรรมและวินัย": "4",
    "ใฝ่เรียนรู้ตลอดชีวิต": "5",
}
# หมวดที่ผู้ดูแลเพิ่มเองทีหลังจะไม่อยู่ในตารางข้างบน แต่ learning_unit_id เป็น NOT NULL
# จึงต้องมีหน่วยรองรับ — ใช้หน่วย 5 ซึ่งเป็นหน่วยกว้างที่สุดของโครงเดิม แล้วจดชื่อหมวดจริง
# ไว้ใน rule_note เพื่อให้ย้อนกลับไปจัดหน่วยให้ถูกทีหลังได้
LEGACY_FALLBACK_UNIT = "5"


@dataclass(frozen=True)
class TalentSpec:
    code: str
    name: str
    plo: str
    sort_order: int


@dataclass(frozen=True)
class RequirementSpec:
    name: str
    unit_code: str
    is_mandatory: bool
    required_hours: float
    talent_code: Optional[str] = None
    # ชื่อกลุ่มของรายการที่ "แชร์เป้าหมายชั่วโมงเดียวกัน" — ไม่ได้เก็บลงฐาน ใช้สองอย่าง:
    # ประกอบข้อความ rule_note และกันไม่ให้การตรวจยอดรวมนับชั่วโมงก้อนเดียวกันซ้ำ
    shared_group: Optional[str] = None
    rule_note: Optional[str] = None
    organizer: Optional[str] = None


# ---------- ชุดเกณฑ์ 2567 หลักสูตรปกติ (60 ชม.) — §9 ----------
TALENTS_2567: list[TalentSpec] = [
    TalentSpec("glocal", "TSU Glocal Talent", "PLO 1", 1),
    TalentSpec("communication", "TSU Communication Talent", "PLO 2", 2),
    TalentSpec("social_innovation", "TSU Social Innovation/Entrepreneurship Talent", "PLO 3", 3),
]

_SOCIAL_PAIR_NOTE = (
    "กฎพิเศษ: «ด้านการสร้างนวัตกรรมสังคม» กับ «ด้านการเป็นผู้ประกอบการ» ใช้เป้าหมาย "
    "16 ชม. ร่วมกัน — เลือกด้านใดด้านหนึ่งให้ครบ 16 ชม. หรือสองด้านรวมกัน ≥ 16 ชม. ก็ได้"
)

REQUIREMENTS_2567_REGULAR: list[RequirementSpec] = [
    # --- Talent 1 · TSU Glocal Talent (PLO 1) รวม 30 ชม. ---
    RequirementSpec("กิจกรรมปฐมนิเทศนิสิต", "5", True, 4, "glocal"),
    RequirementSpec("กิจกรรมเกี่ยวกับการใช้ชีวิตในมหาวิทยาลัย", "4", True, 4, "glocal"),
    RequirementSpec("การคิด วิจารณญาณ และการแก้ปัญหา", "1", False, 3, "glocal"),
    RequirementSpec("การบริหารจัดการตนเอง", "1", False, 3, "glocal"),
    RequirementSpec("การทำงานร่วมกับผู้อื่น", "1", False, 3, "glocal"),
    RequirementSpec("ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล", "5", False, 3, "glocal"),
    RequirementSpec(
        "กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์/สิ่งแวดล้อม)", "2", False, 10, "glocal"
    ),
    # --- Talent 2 · TSU Communication Talent (PLO 2) รวม 10 ชม. ---
    RequirementSpec(
        "ทักษะการใช้ภาษาเพื่อการสื่อสารในชีวิตประจำวัน", "3", False, 10, "communication"
    ),
    # --- Talent 3 · TSU Social Innovation/Entrepreneurship (PLO 3) รวม 20 ชม. ---
    RequirementSpec(
        "แนวคิดการเป็นนักนวัตกรรมสังคม/ผู้ประกอบการ", "5", True, 4, "social_innovation"
    ),
    RequirementSpec(
        "ด้านการสร้างนวัตกรรมสังคม",
        "5",
        False,
        16,
        "social_innovation",
        shared_group="social-16",
        rule_note=_SOCIAL_PAIR_NOTE,
    ),
    RequirementSpec(
        "ด้านการเป็นผู้ประกอบการ",
        "5",
        False,
        16,
        "social_innovation",
        shared_group="social-16",
        rule_note=_SOCIAL_PAIR_NOTE,
    ),
]

# ยอดที่เอกสาร §9 สรุปไว้ — ใช้ตรวจว่าตารางข้างบนยังตรงกับเอกสารทุกครั้งที่รัน
EXPECTED_2567_REGULAR_TOTAL = 60.0
EXPECTED_2567_REGULAR_MANDATORY = 12.0


@dataclass
class Report:
    """สรุปว่ารอบนี้แตะอะไรบ้าง — พิมพ์ท้ายสคริปต์ให้คนรันเห็นผลของการรันซ้ำ."""

    created: list[str] = field(default_factory=list)
    updated: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def _spec_total_hours(specs: list[RequirementSpec]) -> float:
    """ยอดชั่วโมงของชุดเกณฑ์ โดยนับกลุ่มที่แชร์เป้าหมายกันเพียงครั้งเดียว

    สองด้านของ Talent 3 เก็บ required_hours = 16 เท่ากันทั้งคู่ เพราะแต่ละด้านทำคนเดียว
    ให้ครบเกณฑ์ได้ — บวกตรง ๆ จะได้ 76 ซึ่งไม่ใช่ยอดที่นิสิตต้องทำจริง
    """
    total = 0.0
    counted_groups: set[str] = set()
    for spec in specs:
        if spec.shared_group:
            if spec.shared_group in counted_groups:
                continue
            counted_groups.add(spec.shared_group)
        total += spec.required_hours
    return total


def _get_or_create_learning_units(session: Session, report: Report) -> dict[str, LearningUnit]:
    units: dict[str, LearningUnit] = {}
    for code, name in LEARNING_UNITS:
        unit = session.exec(select(LearningUnit).where(LearningUnit.code == code)).first()
        if unit is None:
            unit = LearningUnit(code=code, name=name)
            session.add(unit)
            report.created.append(f"learning_unit {code} {name}")
        elif unit.name != name:
            report.updated.append(f"learning_unit {code}: {unit.name!r} → {name!r}")
            unit.name = name
            session.add(unit)
        units[code] = unit
    session.flush()
    return units


def _upsert_criteria_set(
    session: Session,
    report: Report,
    *,
    code: str,
    academic_year: int,
    program_type: ProgramType,
    name: str,
    total_required_hours: float,
    counting_rule: CountingRule,
) -> CriteriaSet:
    criteria_set = session.exec(select(CriteriaSet).where(CriteriaSet.code == code)).first()
    fields = {
        "academic_year": academic_year,
        "program_type": program_type,
        "name": name,
        "total_required_hours": total_required_hours,
        "counting_rule": counting_rule,
        "is_active": True,
    }
    if criteria_set is None:
        # effective_from/to ปล่อยว่างไว้ตั้งใจ — ตัวเลือกชุดเกณฑ์จริงคือรุ่นของนิสิต (§8)
        # การเดาวันที่ลงไปจะกลายเป็นข้อมูลที่ดูน่าเชื่อแต่ไม่มีใครยืนยัน
        criteria_set = CriteriaSet(code=code, **fields)
        session.add(criteria_set)
        report.created.append(f"criteria_set {code} ({name}, {total_required_hours:g} ชม.)")
    else:
        changed = [k for k, v in fields.items() if getattr(criteria_set, k) != v]
        for key in changed:
            setattr(criteria_set, key, fields[key])
        if changed:
            session.add(criteria_set)
            report.updated.append(f"criteria_set {code}: {', '.join(changed)}")
    session.flush()
    return criteria_set


def _upsert_requirement(
    session: Session,
    report: Report,
    criteria_set: CriteriaSet,
    unit: LearningUnit,
    *,
    name: str,
    is_mandatory: bool,
    required_hours: float,
    talent_id: Optional[int] = None,
    rule_note: Optional[str] = None,
    organizer: Optional[str] = None,
) -> Requirement:
    """สร้าง/อัปเดตรายการเกณฑ์ โดยใช้ (ชุดเกณฑ์, ชื่อ) เป็นกุญแจธรรมชาติ."""
    requirement = session.exec(
        select(Requirement)
        .where(Requirement.criteria_set_id == criteria_set.id)
        .where(Requirement.name == name)
    ).first()
    fields = {
        "talent_id": talent_id,
        "learning_unit_id": unit.id,
        "is_mandatory": is_mandatory,
        "required_hours": required_hours,
        "rule_note": rule_note,
        "organizer": organizer,
    }
    if requirement is None:
        requirement = Requirement(criteria_set_id=criteria_set.id, name=name, **fields)
        session.add(requirement)
        report.created.append(f"requirement [{criteria_set.code}] {name} ({required_hours:g} ชม.)")
    else:
        changed = [k for k, v in fields.items() if getattr(requirement, k) != v]
        for key in changed:
            setattr(requirement, key, fields[key])
        if changed:
            session.add(requirement)
            report.updated.append(f"requirement [{criteria_set.code}] {name}: {', '.join(changed)}")
    session.flush()
    return requirement


def seed_legacy_set(
    session: Session, units: dict[str, LearningUnit], report: Report
) -> Optional[CriteriaSet]:
    """ชุดเกณฑ์เก่า — แปลงจาก hourcategory/hoursubcategory ที่ยังอยู่ในฐาน (§5 ขั้น 3)

    ตั้งใจอ่านจากฐาน ไม่ใช่ hardcode: ผู้ดูแลเพิ่ม/แก้หมวดชั่วโมงเองได้มาตั้งแต่ก่อนหน้านี้
    ฐานของจริงจึงเป็นคำตอบเดียวที่ถูกต้องว่ารุ่นเก่าถูกวัดด้วยอะไร
    """
    categories = session.exec(select(HourCategory)).all()
    if not categories:
        report.warnings.append(
            "ไม่พบ hourcategory ในฐาน — ข้ามชุดเกณฑ์ legacy "
            "(ฐานใหม่เอี่ยมที่ยังไม่ได้รัน seed.py จะเป็นแบบนี้)"
        )
        return None

    total_hours = sum(c.required_hours for c in categories)
    criteria_set = _upsert_criteria_set(
        session,
        report,
        code=LEGACY_CRITERIA_CODE,
        academic_year=2566,
        program_type=ProgramType.regular,
        name="เกณฑ์เดิม (โครงสร้าง 2560–2566) หลักสูตรปกติ",
        total_required_hours=total_hours,
        # โครงเดิมตัดสิน "ผ่าน" จากยอดรวมของแต่ละหมวด ไม่ได้ดูรายหมวดย่อย
        # (ดู gold_student_hours เดิม) จึงเป็น total_per_unit ไม่ใช่ min_per_requirement
        counting_rule=CountingRule.total_per_unit,
    )

    subcategories = session.exec(select(HourSubcategory)).all()
    subs_by_category: dict[int, list[HourSubcategory]] = {}
    for sub in subcategories:
        subs_by_category.setdefault(sub.category_id, []).append(sub)

    for category in sorted(categories, key=lambda c: c.id):
        unit_code = LEGACY_UNIT_BY_CATEGORY.get(category.name)
        note = None
        if unit_code is None:
            unit_code = LEGACY_FALLBACK_UNIT
            note = f"หมวดเดิม «{category.name}» ไม่ตรงหน่วยการเรียนรู้ใด — ตั้งเป็นหน่วย 5 ไว้ก่อน"
            report.warnings.append(note)

        subs = subs_by_category.get(category.id, [])
        if not subs:
            report.warnings.append(f"หมวด «{category.name}» ไม่มีหมวดย่อย — ไม่มีรายการเกณฑ์ให้แปลง")
            continue

        for sub in sorted(subs, key=lambda s: s.id):
            _upsert_requirement(
                session,
                report,
                criteria_set,
                units[unit_code],
                name=sub.name,
                # โครงเดิมไม่มีแนวคิด "บังคับ/เลือก" — ทุกหมวดย่อยเป็นเป้าชั่วโมงเท่ากันหมด
                is_mandatory=False,
                required_hours=sub.required_hours,
                rule_note=note,
            )

        # total_per_unit วัดจากยอดรวมรายการเกณฑ์ในหน่วยนั้น ไม่มีคอลัมน์เป้าหมายรายหน่วย
        # แยกต่างหาก — ยอดจึงต้องเท่ากับ required_hours ของหมวดเดิม ไม่งั้นเกณฑ์รุ่นเก่าเพี้ยน
        subs_total = sum(s.required_hours for s in subs)
        if subs_total != category.required_hours:
            report.warnings.append(
                f"หมวด «{category.name}» ต้องการ {category.required_hours:g} ชม. "
                f"แต่หมวดย่อยรวมได้ {subs_total:g} ชม. — ชุด legacy จะวัดที่ {subs_total:g} ชม."
            )

    return criteria_set


def seed_2567_regular(
    session: Session, units: dict[str, LearningUnit], report: Report
) -> CriteriaSet:
    """ชุดเกณฑ์ 2567 หลักสูตรปกติ + Talent 3 กลุ่ม + รายการเกณฑ์ 11 รายการ (§9)."""
    criteria_set = _upsert_criteria_set(
        session,
        report,
        code="2567-regular",
        academic_year=2567,
        program_type=ProgramType.regular,
        name="เกณฑ์ 2567 หลักสูตรปกติ (60 ชม.)",
        total_required_hours=EXPECTED_2567_REGULAR_TOTAL,
        # §9: "ทำตามชั่วโมงที่ระบุต่อรายการ (บังคับต้องครบทุกตัว)"
        counting_rule=CountingRule.min_per_requirement,
    )

    talent_ids: dict[str, int] = {}
    for spec in TALENTS_2567:
        talent = session.exec(
            select(Talent)
            .where(Talent.criteria_set_id == criteria_set.id)
            .where(Talent.code == spec.code)
        ).first()
        fields = {"name": spec.name, "plo": spec.plo, "sort_order": spec.sort_order}
        if talent is None:
            talent = Talent(criteria_set_id=criteria_set.id, code=spec.code, **fields)
            session.add(talent)
            report.created.append(f"talent {spec.code} ({spec.name}, {spec.plo})")
        else:
            changed = [k for k, v in fields.items() if getattr(talent, k) != v]
            for key in changed:
                setattr(talent, key, fields[key])
            if changed:
                session.add(talent)
                report.updated.append(f"talent {spec.code}: {', '.join(changed)}")
        session.flush()
        talent_ids[spec.code] = talent.id

    for spec in REQUIREMENTS_2567_REGULAR:
        _upsert_requirement(
            session,
            report,
            criteria_set,
            units[spec.unit_code],
            name=spec.name,
            is_mandatory=spec.is_mandatory,
            required_hours=spec.required_hours,
            talent_id=talent_ids[spec.talent_code] if spec.talent_code else None,
            rule_note=spec.rule_note,
            organizer=spec.organizer,
        )

    return criteria_set


def _check_2567_totals(report: Report) -> None:
    total = _spec_total_hours(REQUIREMENTS_2567_REGULAR)
    mandatory = sum(s.required_hours for s in REQUIREMENTS_2567_REGULAR if s.is_mandatory)
    if total != EXPECTED_2567_REGULAR_TOTAL:
        report.warnings.append(
            f"รายการเกณฑ์ 2567-regular รวมได้ {total:g} ชม. แต่เอกสาร §9 ระบุ "
            f"{EXPECTED_2567_REGULAR_TOTAL:g} ชม."
        )
    if mandatory != EXPECTED_2567_REGULAR_MANDATORY:
        report.warnings.append(
            f"รายการบังคับรวมได้ {mandatory:g} ชม. แต่เอกสาร §9 ระบุ "
            f"{EXPECTED_2567_REGULAR_MANDATORY:g} ชม."
        )


def _print_summary(session: Session) -> None:
    print("\n--- สรุปชุดเกณฑ์ในฐานข้อมูล ---")
    for criteria_set in session.exec(select(CriteriaSet).order_by(CriteriaSet.code)).all():
        requirements = session.exec(
            select(Requirement).where(Requirement.criteria_set_id == criteria_set.id)
        ).all()
        talents = session.exec(
            select(Talent).where(Talent.criteria_set_id == criteria_set.id)
        ).all()
        mandatory = sum(r.required_hours for r in requirements if r.is_mandatory)
        print(
            f"  {criteria_set.code}: {criteria_set.total_required_hours:g} ชม. · "
            f"{criteria_set.counting_rule.value} · talent {len(talents)} · "
            f"requirement {len(requirements)} (บังคับ {mandatory:g} ชม.)"
        )

    unassigned = len(
        session.exec(select(Student).where(Student.criteria_set_id.is_(None))).all()
    )
    if unassigned:
        # เจตนาไม่ backfill ที่นี่ — เป็นงานเฟสถัดไปตาม §5 ขั้น 5 แต่รายงานให้เห็นว่ายังค้าง
        print(f"  นิสิตที่ยังไม่ผูกชุดเกณฑ์: {unassigned} คน (backfill ในเฟสถัดไป)")


def populate(session: Session) -> Report:
    """ใส่นิยามเกณฑ์ทั้งหมดลง session ที่ให้มา โดยยังไม่ commit

    แยกจาก ``seed_criteria()`` เพื่อให้เทสต์เรียกด้วย session ของฐานในหน่วยความจำได้
    ไม่ต้องแตะ engine จริง
    """
    report = Report()
    _check_2567_totals(report)
    units = _get_or_create_learning_units(session, report)
    seed_legacy_set(session, units, report)
    seed_2567_regular(session, units, report)
    return report


def seed_criteria(dry_run: bool = False) -> None:
    create_db_and_tables()

    with Session(engine) as session:
        report = populate(session)

        if dry_run:
            session.rollback()
            print("dry-run — ไม่ได้เขียนอะไรลงฐาน")
        else:
            session.commit()

        print(f"สร้างใหม่ {len(report.created)} รายการ · อัปเดต {len(report.updated)} รายการ")
        for line in report.created:
            print(f"  + {line}")
        for line in report.updated:
            print(f"  ~ {line}")
        for line in report.warnings:
            print(f"  ! {line}")

        if not dry_run:
            _print_summary(session)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="seed นิยามชุดเกณฑ์กิจกรรม (เฟส 2)")
    parser.add_argument("--dry-run", action="store_true", help="บอกว่าจะเปลี่ยนอะไร ไม่เขียนจริง")
    args = parser.parse_args()

    seed_criteria(dry_run=args.dry_run)
