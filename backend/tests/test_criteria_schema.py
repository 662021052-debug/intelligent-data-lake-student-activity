"""เฟส 1 ของการรื้อ DB: ชุดเกณฑ์แบบมีเวอร์ชัน

คุมสองเรื่องที่โครงใหม่ต้องทำได้: นิสิตรู้เองว่าอยู่รุ่นไหน/ใช้เกณฑ์ชุดไหนจากรหัส
นิสิต และกิจกรรมหนึ่งงานผูกรายการเกณฑ์ได้หลายรายการ (แทน subcategory เดี่ยว)
"""

from datetime import datetime, timedelta, timezone

import pytest
from sqlmodel import select

from app.criteria import cohort_from_student_id, criteria_set_code_for
from app.models import (
    ActivityRequirement,
    CriteriaSet,
    LearningUnit,
    ProgramType,
    Requirement,
    Talent,
)


def _admin_headers(client):
    response = client.post("/auth/login", data={"username": "admin", "password": "admin123"})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _make_student(client, student_id, **overrides):
    payload = {
        "student_id": student_id,
        "full_name": "ทดสอบ ระบบ",
        "faculty": "คณะวิทยาศาสตร์และนวัตกรรมดิจิทัล",
        "major": "วิทยาการคอมพิวเตอร์",
        "year_level": 1,
        "status": "active",
        **overrides,
    }
    return client.post("/students", json=payload, headers=_admin_headers(client))


def _seed_criteria_set(session, code="2567-regular", counting_hours=60.0):
    criteria_set = CriteriaSet(
        code=code,
        academic_year=2567,
        program_type=ProgramType.regular,
        name="เกณฑ์ 2567 หลักสูตรปกติ",
        total_required_hours=counting_hours,
        effective_from_cohort=2567,
        is_system=True,
    )
    session.add(criteria_set)
    session.commit()
    session.refresh(criteria_set)
    return criteria_set


def _seed_requirement(session, criteria_set, name="กิจกรรมปฐมนิเทศนิสิต", hours=4.0):
    unit = session.exec(select(LearningUnit).where(LearningUnit.code == "5")).first()
    if unit is None:
        unit = LearningUnit(code="5", name="ใฝ่เรียนรู้ตลอดชีวิต")
        session.add(unit)
        session.commit()
        session.refresh(unit)

    requirement = Requirement(
        criteria_set_id=criteria_set.id,
        learning_unit_id=unit.id,
        name=name,
        is_mandatory=True,
        required_hours=hours,
    )
    session.add(requirement)
    session.commit()
    session.refresh(requirement)
    return requirement


# ---------------------------------------------------------------- แมปรหัส → รุ่น/ชุดเกณฑ์


@pytest.mark.parametrize(
    "student_id,expected",
    [
        ("6820510466", 2568),   # ข้อมูลจริง 10 หลัก
        ("6921510120", 2569),
        ("662021052", 2566),    # รหัสรุ่นเก่า 9 หลักยังอ่านได้
        ("", None),
        ("ab12345678", None),
    ],
)
def test_cohort_from_student_id(student_id, expected):
    assert cohort_from_student_id(student_id) == expected


def test_criteria_set_code_for_reads_the_ladder_from_the_database(session):
    """การแมปรุ่น→ชุดอ่านจาก effective_from_cohort ในฐาน ไม่ได้ฝังไว้ในโค้ดแล้ว

    เคสครบ ๆ อยู่ที่ ``tests/test_criteria_resolver.py`` ที่นี่คุมแค่ว่าฟังก์ชันนี้
    ยังตอบตรงกับกติกาเดิมของรุ่น 2566/2567 ซึ่งเป็นข้อมูลจริงที่ใช้อยู่
    """
    session.add(
        CriteriaSet(
            code="legacy-2566",
            academic_year=2566,
            program_type=ProgramType.regular,
            name="เกณฑ์เดิม",
            total_required_hours=60,
            effective_from_cohort=0,
        )
    )
    session.add(
        CriteriaSet(
            code="2567-regular",
            academic_year=2567,
            program_type=ProgramType.regular,
            name="เกณฑ์ 2567",
            total_required_hours=60,
            effective_from_cohort=2567,
        )
    )
    session.commit()

    assert criteria_set_code_for(session, 2566, ProgramType.regular) == "legacy-2566"
    assert criteria_set_code_for(session, 2567, ProgramType.regular) == "2567-regular"
    assert criteria_set_code_for(session, 2569, ProgramType.regular) == "2567-regular"
    assert criteria_set_code_for(session, None, ProgramType.regular) is None


def test_create_student_derives_cohort_and_criteria_set(client, session):
    criteria_set = _seed_criteria_set(session)

    response = _make_student(client, "6920510001")
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["cohort"] == 2569
    assert body["program_type"] == "regular"
    assert body["criteria_set_id"] == criteria_set.id


def test_student_without_matching_criteria_set_is_left_unlinked(client):
    """ยังไม่ได้ seed ชุดเกณฑ์ = ผูกไม่ได้ ต้องปล่อยว่างไว้ ไม่ใช่ล้มทั้งคำขอ."""
    response = _make_student(client, "6620510002")
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["cohort"] == 2566
    assert body["criteria_set_id"] is None


def test_ten_digit_student_id_is_accepted(client):
    response = _make_student(client, "6820910132")
    assert response.status_code == 201, response.text
    assert response.json()["student_id"] == "6820910132"


def test_update_student_id_moves_student_to_matching_criteria_set(client, session):
    legacy = _seed_criteria_set(session, code="legacy-2566")
    current = _seed_criteria_set(session, code="2567-regular")

    created = _make_student(client, "6620510003").json()
    assert created["criteria_set_id"] == legacy.id

    updated = client.put(
        f"/students/{created['id']}",
        json={"student_id": "6920510003"},
        headers=_admin_headers(client),
    )
    assert updated.status_code == 200, updated.text
    body = updated.json()
    assert body["cohort"] == 2569
    assert body["criteria_set_id"] == current.id


# ---------------------------------------------------------------- กิจกรรม ↔ รายการเกณฑ์


def _activity_payload(**overrides):
    start_at = datetime.now(timezone.utc) + timedelta(days=7)
    payload = {
        "name": "อบรมนวัตกรรมสังคม",
        "activity_type": "อบรม",
        "is_required": False,
        "max_participants": 50,
        "start_at": start_at.isoformat(),
        "location": "หอประชุม",
        "hours": 4,
    }
    payload.update(overrides)
    return payload


def test_activity_can_be_linked_to_many_requirements(client, session):
    criteria_set = _seed_criteria_set(session)
    first = _seed_requirement(session, criteria_set, name="กิจกรรมปฐมนิเทศนิสิต")
    second = _seed_requirement(session, criteria_set, name="การทำงานร่วมกับผู้อื่น")

    response = client.post(
        "/activities",
        json=_activity_payload(requirement_ids=[first.id, second.id]),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert sorted(body["requirement_ids"]) == sorted([first.id, second.id])

    links = session.exec(
        select(ActivityRequirement).where(ActivityRequirement.activity_id == body["id"])
    ).all()
    assert len(links) == 2

    # อ่านกลับมาแล้วต้องยังผูกอยู่ ทั้งรายตัวและในรายการ
    single = client.get(f"/activities/{body['id']}")
    assert sorted(single.json()["requirement_ids"]) == sorted([first.id, second.id])
    listed = client.get("/activities").json()["items"]
    assert sorted(listed[0]["requirement_ids"]) == sorted([first.id, second.id])


def test_update_replaces_the_whole_requirement_set(client, session):
    criteria_set = _seed_criteria_set(session)
    first = _seed_requirement(session, criteria_set, name="กิจกรรมปฐมนิเทศนิสิต")
    second = _seed_requirement(session, criteria_set, name="การบริหารจัดการตนเอง")

    created = client.post(
        "/activities", json=_activity_payload(requirement_ids=[first.id])
    ).json()

    updated = client.put(
        f"/activities/{created['id']}", json={"requirement_ids": [second.id]}
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["requirement_ids"] == [second.id]

    # ไม่ส่ง requirement_ids มา = ไม่แตะของเดิม
    renamed = client.put(f"/activities/{created['id']}", json={"name": "ชื่อใหม่"})
    assert renamed.json()["requirement_ids"] == [second.id]

    # ชุดใหม่ที่ยังมีตัวเดิมปนอยู่ต้องไม่ชนคีย์ซ้ำ
    overlapped = client.put(
        f"/activities/{created['id']}", json={"requirement_ids": [second.id, first.id]}
    )
    assert overlapped.status_code == 200, overlapped.text
    assert sorted(overlapped.json()["requirement_ids"]) == sorted([first.id, second.id])


def test_unknown_requirement_id_is_rejected(client):
    response = client.post("/activities", json=_activity_payload(requirement_ids=[999]))
    assert response.status_code == 400
    assert "999" in response.json()["detail"]


def test_activity_must_be_classified_somehow(client):
    """ไม่ผูกรายการเกณฑ์และไม่ระบุหมวดย่อยเดิม = กิจกรรมที่ไม่นับชั่วโมงให้ใครเลย."""
    response = client.post("/activities", json=_activity_payload())
    assert response.status_code == 422


def test_talent_belongs_to_a_criteria_set(session):
    """Talent/PLO เป็นของชุดเกณฑ์ ไม่ใช่ค่ากลางของทั้งระบบ."""
    criteria_set = _seed_criteria_set(session)
    talent = Talent(
        criteria_set_id=criteria_set.id,
        code="glocal",
        name="TSU Glocal Talent",
        plo="PLO 1",
        sort_order=1,
    )
    session.add(talent)
    session.commit()
    session.refresh(talent)

    assert talent.criteria_set_id == criteria_set.id
    requirement = _seed_requirement(session, criteria_set)
    requirement.talent_id = talent.id
    session.add(requirement)
    session.commit()
    session.refresh(requirement)
    assert requirement.talent_id == talent.id
