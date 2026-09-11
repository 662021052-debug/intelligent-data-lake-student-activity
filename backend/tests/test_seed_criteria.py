"""เฟส 2: seed นิยามชุดเกณฑ์

สิ่งที่ต้องคุม: ตัวเลขใน §9 ลงฐานครบและรวมได้ 60/12 ชม. · ชุด legacy แปลงมาจาก
หมวดชั่วโมงที่อยู่ในฐานจริง ไม่ใช่ค่าที่ hardcode ไว้ · และรันซ้ำแล้วไม่เกิดของซ้ำ
เพราะสคริปต์นี้ถูกเรียกทุกครั้งที่คอนเทนเนอร์บูต
"""

from sqlmodel import select

from app.criteria import LEGACY_CRITERIA_CODE
from app.models import (
    CountingRule,
    CriteriaSet,
    HourCategory,
    HourSubcategory,
    LearningUnit,
    ProgramType,
    Requirement,
    Talent,
)
from seed_criteria import (
    EXPECTED_2567_REGULAR_MANDATORY,
    EXPECTED_2567_REGULAR_TOTAL,
    REQUIREMENTS_2567_REGULAR,
    _spec_total_hours,
    populate,
)


def _legacy_hour_structure(session):
    """หมวดชั่วโมงแบบเดิมย่อ ๆ พอให้การแปลง legacy มีต้นทางให้แปลง."""
    structure = [
        ("พัฒนาทักษะชีวิต", 12, [("กิจกรรมเสริมสร้างคุณค่าแห่งตน", 8), ("กิจกรรมบูรณาการ 1", 4)]),
        ("TSU รับใช้สังคม", 12, [("กิจกรรม TSU DO D", 12)]),
    ]
    for name, hours, subs in structure:
        category = HourCategory(name=name, required_hours=hours)
        session.add(category)
        session.commit()
        session.refresh(category)
        for sub_name, sub_hours in subs:
            session.add(
                HourSubcategory(
                    category_id=category.id, name=sub_name, required_hours=sub_hours
                )
            )
    session.commit()


def _requirements(session, code):
    criteria_set = session.exec(select(CriteriaSet).where(CriteriaSet.code == code)).first()
    assert criteria_set is not None, f"ไม่พบชุดเกณฑ์ {code}"
    return criteria_set, session.exec(
        select(Requirement).where(Requirement.criteria_set_id == criteria_set.id)
    ).all()


def test_spec_totals_match_the_design_doc():
    """ตารางใน §9 ต้องรวมได้ 60 ชม. โดยสองด้านของ Talent 3 นับเป็นก้อน 16 ชม. ก้อนเดียว."""
    assert _spec_total_hours(REQUIREMENTS_2567_REGULAR) == EXPECTED_2567_REGULAR_TOTAL
    mandatory = sum(s.required_hours for s in REQUIREMENTS_2567_REGULAR if s.is_mandatory)
    assert mandatory == EXPECTED_2567_REGULAR_MANDATORY
    # บวกตรง ๆ ได้ 76 เพราะสองด้านเก็บ 16 เท่ากันทั้งคู่ — ตัวเลขนี้ต้องไม่หลุดไปเป็นเป้าหมาย
    assert sum(s.required_hours for s in REQUIREMENTS_2567_REGULAR) == 76


def test_seeds_five_learning_units(session):
    report = populate(session)
    session.commit()

    units = session.exec(select(LearningUnit).order_by(LearningUnit.code)).all()
    assert [u.code for u in units] == ["1", "2", "3", "4", "5"]
    assert units[4].name == "ใฝ่เรียนรู้ตลอดชีวิต"
    assert not report.warnings or all("hourcategory" in w for w in report.warnings)


def test_2567_regular_set_matches_section_9(session):
    populate(session)
    session.commit()

    criteria_set, requirements = _requirements(session, "2567-regular")
    assert criteria_set.total_required_hours == 60
    assert criteria_set.program_type == ProgramType.regular
    assert criteria_set.academic_year == 2567
    # §9 นับ "ทำตามชั่วโมงที่ระบุต่อรายการ" ไม่ใช่ยอดรวมรายหน่วยแบบเกณฑ์เก่า
    assert criteria_set.counting_rule == CountingRule.min_per_requirement

    assert len(requirements) == 11
    mandatory = [r for r in requirements if r.is_mandatory]
    assert sorted(r.name for r in mandatory) == sorted(
        [
            "กิจกรรมปฐมนิเทศนิสิต",
            "กิจกรรมเกี่ยวกับการใช้ชีวิตในมหาวิทยาลัย",
            "แนวคิดการเป็นนักนวัตกรรมสังคม/ผู้ประกอบการ",
        ]
    )
    assert sum(r.required_hours for r in mandatory) == 12


def test_2567_talents_carry_plo_and_own_their_requirements(session):
    populate(session)
    session.commit()

    criteria_set, requirements = _requirements(session, "2567-regular")
    talents = session.exec(
        select(Talent)
        .where(Talent.criteria_set_id == criteria_set.id)
        .order_by(Talent.sort_order)
    ).all()
    assert [t.code for t in talents] == ["glocal", "communication", "social_innovation"]
    assert [t.plo for t in talents] == ["PLO 1", "PLO 2", "PLO 3"]

    hours_by_talent = {t.id: 0.0 for t in talents}
    for requirement in requirements:
        assert requirement.talent_id is not None, f"{requirement.name} ไม่ได้อยู่กลุ่ม Talent ใด"
        hours_by_talent[requirement.talent_id] += requirement.required_hours
    # Glocal 30 · Communication 10 · Social 4 + 16 + 16 (สองด้านเก็บเลขเดียวกันทั้งคู่)
    assert [hours_by_talent[t.id] for t in talents] == [30, 10, 36]


def test_social_pair_rule_is_recorded_on_both_sides(session):
    """กฎ "สองด้านรวมกัน ≥ 16" ยังไม่มีที่เก็บเชิงโครงสร้าง ต้องไม่หายไปเงียบ ๆ."""
    populate(session)
    session.commit()

    _, requirements = _requirements(session, "2567-regular")
    pair = [r for r in requirements if r.name.startswith("ด้านการ")]
    assert len(pair) == 2
    for requirement in pair:
        assert requirement.required_hours == 16
        assert requirement.rule_note and "16" in requirement.rule_note


def test_legacy_set_is_converted_from_the_hour_categories_in_the_database(session):
    _legacy_hour_structure(session)
    populate(session)
    session.commit()

    criteria_set, requirements = _requirements(session, LEGACY_CRITERIA_CODE)
    # 12 + 12 จากหมวดที่ใส่ไว้ ไม่ใช่ 60 ของโครงเต็ม — พิสูจน์ว่าอ่านจากฐานจริง
    assert criteria_set.total_required_hours == 24
    assert criteria_set.counting_rule == CountingRule.total_per_unit
    assert sorted(r.name for r in requirements) == sorted(
        ["กิจกรรมเสริมสร้างคุณค่าแห่งตน", "กิจกรรมบูรณาการ 1", "กิจกรรม TSU DO D"]
    )

    units = {u.id: u.code for u in session.exec(select(LearningUnit)).all()}
    unit_by_name = {r.name: units[r.learning_unit_id] for r in requirements}
    assert unit_by_name["กิจกรรมเสริมสร้างคุณค่าแห่งตน"] == "1"
    assert unit_by_name["กิจกรรม TSU DO D"] == "2"
    # โครงเดิมไม่มีแนวคิดบังคับ/เลือก — แปลงมาแล้วต้องไม่กลายเป็นบังคับขึ้นมาเอง
    assert not any(r.is_mandatory for r in requirements)


def test_legacy_unit_total_must_match_the_old_category_target(session):
    """total_per_unit วัดจากยอดรวมรายการเกณฑ์ในหน่วย ถ้าไม่ตรงเป้าหมวดเดิมต้องเตือน."""
    category = HourCategory(name="พัฒนาทักษะชีวิต", required_hours=12)
    session.add(category)
    session.commit()
    session.refresh(category)
    session.add(HourSubcategory(category_id=category.id, name="กิจกรรมเดียว", required_hours=5))
    session.commit()

    report = populate(session)
    session.commit()

    assert any("พัฒนาทักษะชีวิต" in w and "5" in w for w in report.warnings)


def test_unknown_legacy_category_lands_on_a_unit_and_says_so(session):
    """หมวดที่ผู้ดูแลเพิ่มเองไม่ตรงหน่วยใด — ต้องแปลงต่อได้ ไม่ใช่ล้มทั้งสคริปต์."""
    category = HourCategory(name="หมวดที่ผู้ดูแลเพิ่มเอง", required_hours=6)
    session.add(category)
    session.commit()
    session.refresh(category)
    session.add(HourSubcategory(category_id=category.id, name="กิจกรรมพิเศษ", required_hours=6))
    session.commit()

    report = populate(session)
    session.commit()

    _, requirements = _requirements(session, LEGACY_CRITERIA_CODE)
    special = next(r for r in requirements if r.name == "กิจกรรมพิเศษ")
    assert special.learning_unit_id is not None
    assert special.rule_note and "หมวดที่ผู้ดูแลเพิ่มเอง" in special.rule_note
    assert any("หมวดที่ผู้ดูแลเพิ่มเอง" in w for w in report.warnings)


def test_running_twice_changes_nothing(session):
    """สคริปต์นี้รันทุกครั้งที่คอนเทนเนอร์บูต รอบสองต้องไม่สร้างของซ้ำ."""
    _legacy_hour_structure(session)
    populate(session)
    session.commit()

    before = {
        "criteria_set": len(session.exec(select(CriteriaSet)).all()),
        "talent": len(session.exec(select(Talent)).all()),
        "learning_unit": len(session.exec(select(LearningUnit)).all()),
        "requirement": len(session.exec(select(Requirement)).all()),
    }

    second = populate(session)
    session.commit()

    after = {
        "criteria_set": len(session.exec(select(CriteriaSet)).all()),
        "talent": len(session.exec(select(Talent)).all()),
        "learning_unit": len(session.exec(select(LearningUnit)).all()),
        "requirement": len(session.exec(select(Requirement)).all()),
    }
    assert after == before
    assert second.created == []
    assert second.updated == []


def test_rerun_repairs_a_hand_edited_requirement(session):
    """ค่าที่ถูกแก้จนไม่ตรงเอกสาร ต้องถูกดึงกลับ — ไม่งั้นเกณฑ์ค่อย ๆ เพี้ยนไปเงียบ ๆ."""
    populate(session)
    session.commit()

    _, requirements = _requirements(session, "2567-regular")
    orientation = next(r for r in requirements if r.name == "กิจกรรมปฐมนิเทศนิสิต")
    orientation.required_hours = 99
    orientation.is_mandatory = False
    session.add(orientation)
    session.commit()

    report = populate(session)
    session.commit()

    session.refresh(orientation)
    assert orientation.required_hours == 4
    assert orientation.is_mandatory is True
    assert any("กิจกรรมปฐมนิเทศนิสิต" in line for line in report.updated)


def test_extra_requirements_added_by_hand_are_left_alone(session):
    """เพิ่มรายการเกณฑ์เองแล้วบูตใหม่ ต้องไม่ถูกสคริปต์ลบทิ้ง."""
    populate(session)
    session.commit()

    criteria_set, _ = _requirements(session, "2567-regular")
    unit = session.exec(select(LearningUnit).where(LearningUnit.code == "1")).first()
    session.add(
        Requirement(
            criteria_set_id=criteria_set.id,
            learning_unit_id=unit.id,
            name="รายการที่คณะเพิ่มเอง",
            required_hours=2,
        )
    )
    session.commit()

    populate(session)
    session.commit()

    _, requirements = _requirements(session, "2567-regular")
    assert any(r.name == "รายการที่คณะเพิ่มเอง" for r in requirements)
