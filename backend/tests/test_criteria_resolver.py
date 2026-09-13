"""เฟส 1 ของการจัดการชุดเกณฑ์: การแมป "รุ่นนิสิต → ชุดเกณฑ์" แบบอ่านจากข้อมูล

กติกาเดิมฝังอยู่ในโค้ด (``cohort >= 2567``) การเพิ่มชุดของรุ่นถัดไปจึงต้องแก้โปรแกรม
ตอนนี้แต่ละชุดบอกเองว่าเริ่มใช้รุ่นไหนผ่าน ``effective_from_cohort`` แล้วตัวแมปเลือก
"ขั้นบันไดที่สูงสุดแต่ยังไม่เกินรุ่นของนิสิต"

เคสที่ต้องคุมให้แน่น เพราะแตะตรงนี้ = กระทบการคำนวณความครบเกณฑ์ของนิสิตทุกคน:
รุ่นเดิมต้องแมปเหมือนเดิมเป๊ะ และชุดของรุ่นอนาคตต้องมีผลทันทีที่เพิ่มแถว โดยไม่แก้โค้ด
"""

import pytest
from sqlmodel import select

from app.criteria import (
    LEGACY_CRITERIA_CODE,
    criteria_set_code_for,
    resolve_criteria_set,
    resolve_criteria_set_id,
)
from app.models import CountingRule, CriteriaSet, ProgramType, Student


def _criteria_set(
    session,
    *,
    code,
    effective_from_cohort,
    program_type=ProgramType.regular,
    is_active=True,
    is_system=True,
):
    criteria_set = CriteriaSet(
        code=code,
        academic_year=max(effective_from_cohort, 2566),
        program_type=program_type,
        name=f"ชุดทดสอบ {code}",
        total_required_hours=60,
        counting_rule=CountingRule.min_per_requirement,
        effective_from_cohort=effective_from_cohort,
        is_active=is_active,
        is_system=is_system,
    )
    session.add(criteria_set)
    session.commit()
    session.refresh(criteria_set)
    return criteria_set


@pytest.fixture(name="ladder")
def ladder_fixture(session):
    """บันไดสองขั้นแบบที่ใช้อยู่จริง: legacy (รุ่น 0 ขึ้นไป) และ 2567 (รุ่น 2567 ขึ้นไป)"""
    legacy = _criteria_set(session, code=LEGACY_CRITERIA_CODE, effective_from_cohort=0)
    modern = _criteria_set(session, code="2567-regular", effective_from_cohort=2567)
    return {"legacy": legacy, "2567": modern}


# --------------------------- บันไดพื้นฐาน ---------------------------
@pytest.mark.parametrize(
    "cohort,expected",
    [
        (2560, LEGACY_CRITERIA_CODE),
        (2565, LEGACY_CRITERIA_CODE),
        (2566, LEGACY_CRITERIA_CODE),   # ขั้นสุดท้ายก่อนเปลี่ยนเกณฑ์
        (2567, "2567-regular"),          # ปีแรกที่ชุดใหม่เริ่มใช้ = เข้าชุดใหม่ทันที
        (2568, "2567-regular"),
        (2569, "2567-regular"),
    ],
)
def test_cohort_maps_to_the_highest_set_that_has_started(session, ladder, cohort, expected):
    assert criteria_set_code_for(session, cohort) == expected


def test_unknown_cohort_resolves_to_nothing(session, ladder):
    """รหัสนิสิตอ่านรุ่นไม่ออก = ยังตัดสินไม่ได้ ต้องไม่เดาไปที่ชุดใดชุดหนึ่ง"""
    assert resolve_criteria_set(session, None) is None
    assert criteria_set_code_for(session, None) is None


def test_no_criteria_sets_at_all_resolves_to_nothing(session):
    assert criteria_set_code_for(session, 2569) is None
    assert resolve_criteria_set_id(session, "6920510001") is None


# --------------------------- เพิ่มชุดรุ่นอนาคตโดยไม่แก้โค้ด ---------------------------
def test_a_new_set_takes_over_its_cohorts_without_touching_code(session, ladder):
    """หัวใจของเฟสนี้ — เพิ่มแถวชุด 2570 แล้วรุ่น 70 ขึ้นไปต้องย้ายไปเองทันที"""
    assert criteria_set_code_for(session, 2570) == "2567-regular"  # ก่อนเพิ่ม

    _criteria_set(session, code="2570-regular", effective_from_cohort=2570)

    assert criteria_set_code_for(session, 2570) == "2570-regular"
    assert criteria_set_code_for(session, 2571) == "2570-regular"
    # รุ่นก่อนหน้าต้องไม่ขยับตาม
    assert criteria_set_code_for(session, 2569) == "2567-regular"
    assert criteria_set_code_for(session, 2566) == LEGACY_CRITERIA_CODE


def test_a_custom_set_is_used_just_like_a_system_set(session, ladder):
    """is_system มีผลแค่กับ seed ไม่ได้แปลว่าชุดนั้นถูกใช้งานจริงน้อยกว่า"""
    custom = _criteria_set(
        session, code="2570-custom", effective_from_cohort=2570, is_system=False
    )

    assert resolve_criteria_set(session, 2570).id == custom.id


# --------------------------- กรณีขอบ ---------------------------
def test_inactive_sets_are_skipped(session, ladder):
    """ปิดชุดที่ยกเลิกแล้วต้องทำให้รุ่นนั้นตกกลับไปขั้นก่อนหน้า ไม่ใช่ยังใช้ต่อ"""
    _criteria_set(
        session, code="2570-เลิกใช้", effective_from_cohort=2570, is_active=False
    )

    assert criteria_set_code_for(session, 2570) == "2567-regular"


def test_each_program_type_walks_its_own_ladder(session, ladder):
    continuing = _criteria_set(
        session,
        code="2567-continuing",
        effective_from_cohort=2567,
        program_type=ProgramType.continuing,
    )

    assert resolve_criteria_set(session, 2568, ProgramType.continuing).id == continuing.id
    assert resolve_criteria_set(session, 2568, ProgramType.regular).id == ladder["2567"].id


def test_a_program_type_with_no_set_of_its_own_falls_back_to_legacy(session, ladder):
    """หลักสูตรต่อเนื่องยังไม่มีชุดของตัวเอง — ต้องได้เกณฑ์เก่า ไม่ใช่ NULL

    ปล่อยเป็น NULL จะทำให้ทั้งระบบคำนวณความครบเกณฑ์ของคนกลุ่มนั้นไม่ได้เลย
    """
    found = resolve_criteria_set(session, 2569, ProgramType.continuing)

    assert found is not None
    assert found.code == LEGACY_CRITERIA_CODE


def test_the_legacy_fallback_respects_is_active_too(session):
    """ปิดเกณฑ์เก่าแล้วต้องไม่ถูกหยิบมาใช้ทางประตูหลัง — ไม่งั้น is_active โกหก"""
    _criteria_set(
        session, code=LEGACY_CRITERIA_CODE, effective_from_cohort=0, is_active=False
    )

    assert resolve_criteria_set(session, 2569, ProgramType.continuing) is None


def test_ties_resolve_the_same_way_every_time(session, ladder):
    """สองชุดเริ่มรุ่นเดียวกัน (ข้อมูลเก่าที่หลุดมาก่อนมีกฎห้ามซ้ำ) ต้องไม่สลับไปมา"""
    _criteria_set(session, code="2567-ซ้ำ", effective_from_cohort=2567)

    first = criteria_set_code_for(session, 2568)
    assert first == criteria_set_code_for(session, 2568)
    assert first == "2567-ซ้ำ", "ตัวที่เพิ่มทีหลังชนะ (id มากกว่า) — ขอแค่ให้คงที่"


# --------------------------- ผ่านรหัสนิสิตจริง ---------------------------
@pytest.mark.parametrize(
    "student_id,expected",
    [
        ("6620510001", LEGACY_CRITERIA_CODE),   # รหัส 66 → เกณฑ์เดิม
        ("6820510466", "2567-regular"),          # รหัส 68 → ชุด 2567 (ข้อมูลจริงส่วนใหญ่)
        ("6920910247", "2567-regular"),          # รหัส 69 → ชุด 2567
    ],
)
def test_student_id_resolves_through_its_cohort(session, ladder, student_id, expected):
    resolved = resolve_criteria_set_id(session, student_id)

    assert resolved is not None
    assert session.get(CriteriaSet, resolved).code == expected


def test_students_created_through_the_api_keep_the_same_set_as_before(client, session, ladder):
    """ยืนยันว่าการเปลี่ยนมาใช้ข้อมูลไม่ได้ทำให้นิสิตย้ายชุด (รหัส 69 ต้องอยู่ชุด 2567 เหมือนเดิม)"""
    response = client.post(
        "/students",
        json={
            "student_id": "6920510001",
            "full_name": "ทดสอบ ระบบ",
            "faculty": "คณะวิศวกรรมศาสตร์",
            "major": "วิศวกรรมคอมพิวเตอร์",
            "year_level": 1,
            "status": "active",
        },
        headers={
            "Authorization": "Bearer "
            + client.post(
                "/auth/login", data={"username": "admin", "password": "admin123"}
            ).json()["access_token"]
        },
    )

    assert response.status_code == 201, response.text
    assert response.json()["criteria_set_id"] == ladder["2567"].id

    student = session.exec(
        select(Student).where(Student.student_id == "6920510001")
    ).first()
    assert student.cohort == 2569
