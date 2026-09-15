"""เฟส 2 ของการจัดการชุดเกณฑ์: API เขียนชุดเกณฑ์ (admin เท่านั้น)

สิ่งที่ต้องคุมคือ "กันพลาด" มากกว่า "สร้างได้" — ชุดเกณฑ์คือสิ่งที่ใช้วัดนิสิตทุกคน
พลาดแต่ละอย่างตามแก้ยาก: แก้ของทางการทับ · ลบชุดที่มีคนใช้อยู่ · ปีรุ่นซ้ำจนบันได
การแมปมีสองขั้นความสูงเท่ากัน
"""

import pytest
from sqlmodel import select

from app.models import (
    ActivityRequirement,
    CountingRule,
    CriteriaSet,
    LearningUnit,
    ProgramType,
    Requirement,
    RequirementGroup,
    Student,
    StudentStatus,
    Talent,
)


def _admin_headers(client):
    response = client.post("/auth/login", data={"username": "admin", "password": "admin123"})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _set_payload(**overrides):
    payload = {
        "code": "2570-regular",
        "name": "เกณฑ์ 2570 หลักสูตรปกติ",
        "academic_year": 2570,
        "program_type": "regular",
        "effective_from_cohort": 2570,
        "total_required_hours": 60,
        "counting_rule": "min_per_requirement",
    }
    payload.update(overrides)
    return payload


def _create_set(client, **overrides):
    return client.post(
        "/criteria-sets", json=_set_payload(**overrides), headers=_admin_headers(client)
    )


@pytest.fixture(name="unit")
def unit_fixture(session):
    unit = session.exec(select(LearningUnit).where(LearningUnit.code == "5")).first()
    if unit is None:
        unit = LearningUnit(code="5", name="ใฝ่เรียนรู้ตลอดชีวิต")
        session.add(unit)
        session.commit()
        session.refresh(unit)
    return unit


@pytest.fixture(name="system_set")
def system_set_fixture(session):
    """ชุดเกณฑ์ทางการที่ seed สร้าง — ต้องแตะไม่ได้"""
    criteria_set = CriteriaSet(
        code="2567-regular",
        name="เกณฑ์ 2567 หลักสูตรปกติ",
        academic_year=2567,
        program_type=ProgramType.regular,
        effective_from_cohort=2567,
        total_required_hours=60,
        counting_rule=CountingRule.min_per_requirement,
        is_system=True,
    )
    session.add(criteria_set)
    session.commit()
    session.refresh(criteria_set)
    return criteria_set


# --------------------------- สร้าง / แก้ / ลบ ชุดเกณฑ์ ---------------------------
def test_admin_creates_a_custom_set(client):
    response = _create_set(client)

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["code"] == "2570-regular"
    assert body["effective_from_cohort"] == 2570
    # ชุดที่สร้างผ่าน API ต้องไม่ใช่ชุดระบบ ไม่งั้น seed จะมาเขียนทับทีหลัง
    assert body["is_system"] is False


def test_created_set_is_used_by_the_resolver_right_away(client, session):
    """หัวใจของทั้งเฟส 1+2 — สร้างชุดแล้วนิสิตรุ่นนั้นต้องแมปเข้าชุดใหม่เอง"""
    from app.criteria import criteria_set_code_for

    session.add(
        CriteriaSet(
            code="legacy-2566",
            name="เกณฑ์เดิม",
            academic_year=2566,
            program_type=ProgramType.regular,
            effective_from_cohort=0,
            total_required_hours=60,
            is_system=True,
        )
    )
    session.commit()
    assert criteria_set_code_for(session, 2570) == "legacy-2566"

    assert _create_set(client).status_code == 201

    assert criteria_set_code_for(session, 2570) == "2570-regular"
    assert criteria_set_code_for(session, 2566) == "legacy-2566", "รุ่นเก่าต้องไม่ขยับ"


def test_admin_updates_a_custom_set(client):
    created = _create_set(client).json()

    response = client.put(
        f"/criteria-sets/{created['id']}",
        json=_set_payload(name="เกณฑ์ 2570 (แก้ชื่อแล้ว)", total_required_hours=72),
        headers=_admin_headers(client),
    )

    assert response.status_code == 200, response.text
    assert response.json()["name"] == "เกณฑ์ 2570 (แก้ชื่อแล้ว)"
    assert response.json()["total_required_hours"] == 72


def test_admin_deletes_a_custom_set_with_its_contents(client, session, unit):
    created = _create_set(client).json()
    talent = client.post(
        f"/criteria-sets/{created['id']}/talents",
        json={"code": "glocal", "name": "TSU Glocal Talent", "plo": "PLO 1", "sort_order": 1},
        headers=_admin_headers(client),
    ).json()
    client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={
            "name": "กิจกรรมปฐมนิเทศ",
            "learning_unit_id": unit.id,
            "talent_id": talent["id"],
            "required_hours": 4,
        },
        headers=_admin_headers(client),
    )

    response = client.delete(f"/criteria-sets/{created['id']}", headers=_admin_headers(client))

    assert response.status_code == 204
    assert session.get(CriteriaSet, created["id"]) is None
    # ของข้างในต้องหายตามไป ไม่ใช่ค้างเป็นแถวกำพร้า
    assert session.exec(
        select(Talent).where(Talent.criteria_set_id == created["id"])
    ).all() == []
    assert session.exec(
        select(Requirement).where(Requirement.criteria_set_id == created["id"])
    ).all() == []


# --------------------------- ตัวชุดทางการ: แก้ระดับชุด/ลบไม่ได้ (ของข้างในแก้ได้) ---------------------------
def test_system_set_cannot_be_updated(client, system_set):
    response = client.put(
        f"/criteria-sets/{system_set.id}",
        json=_set_payload(code="2567-regular", name="แอบแก้ของทางการ"),
        headers=_admin_headers(client),
    )

    assert response.status_code == 403
    assert "เกณฑ์ทางการ" in response.json()["detail"]


def test_system_set_cannot_be_deleted(client, system_set):
    response = client.delete(f"/criteria-sets/{system_set.id}", headers=_admin_headers(client))

    assert response.status_code == 403


def test_contents_of_a_system_set_are_editable(client, session, system_set, unit):
    """ผู้ดูแลแก้ Talent / กลุ่มแชร์เป้า / รายการเกณฑ์ในชุดทางการ (2567) ได้เหมือนชุดของตัวเอง

    ปลอดภัยเพราะ seed_criteria.py ไม่เขียนทับชุดที่มีอยู่แล้ว — แก้แล้วอยู่ ไม่หายตอนบูต
    (คุมไว้ใน test_seed_criteria.py::test_rerun_keeps_an_admin_edited_requirement)
    """
    talent = Talent(criteria_set_id=system_set.id, code="glocal", name="Glocal")
    group = RequirementGroup(
        criteria_set_id=system_set.id, code="social-16", name="กลุ่ม Social", required_hours=16
    )
    session.add(talent)
    session.add(group)
    session.commit()
    session.refresh(talent)
    session.refresh(group)
    requirement = Requirement(
        criteria_set_id=system_set.id,
        name="กิจกรรมปฐมนิเทศนิสิต",
        learning_unit_id=unit.id,
        required_hours=4,
    )
    session.add(requirement)
    session.commit()
    session.refresh(requirement)

    headers = _admin_headers(client)

    # เพิ่ม
    new_talent = client.post(
        f"/criteria-sets/{system_set.id}/talents",
        json={"code": "new", "name": "เพิ่มใหม่"},
        headers=headers,
    )
    assert new_talent.status_code == 201, new_talent.text
    new_requirement = client.post(
        f"/criteria-sets/{system_set.id}/requirements",
        json={"name": "รายการที่เพิ่มในชุด 2567", "learning_unit_id": unit.id, "required_hours": 2},
        headers=headers,
    )
    assert new_requirement.status_code == 201, new_requirement.text

    # แก้ — และค่าต้องลงฐานจริง
    assert client.put(
        f"/talents/{talent.id}",
        json={"code": "glocal", "name": "แก้ชื่อ", "sort_order": 0},
        headers=headers,
    ).status_code == 200
    assert client.put(
        f"/requirement-groups/{group.id}",
        json={"code": "social-16", "name": "แก้ชื่อกลุ่ม", "required_hours": 20},
        headers=headers,
    ).status_code == 200
    response = client.put(
        f"/requirements/{requirement.id}",
        json={"name": "แก้ชื่อรายการ", "learning_unit_id": unit.id, "required_hours": 6},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    session.expire_all()
    assert session.get(Talent, talent.id).name == "แก้ชื่อ"
    assert session.get(RequirementGroup, group.id).required_hours == 20
    edited = session.get(Requirement, requirement.id)
    assert (edited.name, edited.required_hours) == ("แก้ชื่อรายการ", 6)

    # ลบ
    assert client.delete(f"/requirements/{requirement.id}", headers=headers).status_code == 204
    assert client.delete(
        f"/requirements/{new_requirement.json()['id']}", headers=headers
    ).status_code == 204
    assert client.delete(f"/requirement-groups/{group.id}", headers=headers).status_code == 204
    assert client.delete(f"/talents/{talent.id}", headers=headers).status_code == 204
    assert client.delete(
        f"/talents/{new_talent.json()['id']}", headers=headers
    ).status_code == 204
    session.expire_all()
    assert session.get(CriteriaSet, system_set.id) is not None, "ลบของข้างใน ไม่ใช่ลบชุด"


def test_content_rules_still_apply_inside_a_system_set(client, session, system_set, unit):
    """ปลดล็อกแล้วกฎกันพลาดเดิมต้องยังทำงานกับชุดทางการ — ลบรายการที่กิจกรรมผูกอยู่ไม่ได้"""
    from app.models import Activity, ApprovalStatus, User, UserRole
    from datetime import datetime

    requirement = Requirement(
        criteria_set_id=system_set.id, name="กิจกรรมปฐมนิเทศนิสิต", learning_unit_id=unit.id, required_hours=4
    )
    session.add(requirement)
    session.commit()
    session.refresh(requirement)
    staff = session.exec(select(User).where(User.role == UserRole.staff)).first()
    activity = Activity(
        name="ปฐมนิเทศ",
        activity_type="วิชาการ",
        max_participants=10,
        start_at=datetime(2026, 7, 1, 9),
        location="หอประชุม",
        hours=4,
        created_by=staff.id,
        approval_status=ApprovalStatus.approved,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    session.add(ActivityRequirement(activity_id=activity.id, requirement_id=requirement.id))
    session.commit()

    response = client.delete(f"/requirements/{requirement.id}", headers=_admin_headers(client))

    assert response.status_code == 400
    assert "ผูก" in response.json()["detail"]


# --------------------------- กันลบชุดที่มีคนใช้ ---------------------------
def test_cannot_delete_a_set_that_students_are_assigned_to(client, session):
    created = _create_set(client).json()
    for code in ("7020510001", "7020510002", "7020510003"):
        session.add(
            Student(
                student_id=code,
                full_name=f"นิสิต {code}",
                faculty="คณะวิศวกรรมศาสตร์",
                major="วิศวกรรมคอมพิวเตอร์",
                year_level=1,
                status=StudentStatus.active,
                criteria_set_id=created["id"],
            )
        )
    session.commit()

    response = client.delete(f"/criteria-sets/{created['id']}", headers=_admin_headers(client))

    assert response.status_code == 400
    # ต้องบอกจำนวนด้วย ผู้ดูแลจะได้รู้ว่าต้องย้ายกี่คนก่อน
    assert "3" in response.json()["detail"]
    assert session.get(CriteriaSet, created["id"]) is not None


def test_cannot_delete_a_set_whose_requirements_activities_point_at(
    client, session, unit
):
    created = _create_set(client).json()
    requirement = client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={"name": "รายการที่มีกิจกรรมผูกอยู่", "learning_unit_id": unit.id,
              "required_hours": 4},
        headers=_admin_headers(client),
    ).json()

    from tests.test_activities import make_activity

    activity = make_activity(client, name="กิจกรรมที่ผูกเกณฑ์").json()
    session.add(
        ActivityRequirement(activity_id=activity["id"], requirement_id=requirement["id"])
    )
    session.commit()

    response = client.delete(f"/criteria-sets/{created['id']}", headers=_admin_headers(client))

    assert response.status_code == 400
    assert "กิจกรรม" in response.json()["detail"]


# --------------------------- ปีรุ่นห้ามซ้ำ ---------------------------
def test_two_sets_cannot_start_at_the_same_cohort(client):
    assert _create_set(client).status_code == 201

    response = _create_set(client, code="2570-อีกชุด", name="ชุดซ้ำปีรุ่น")

    assert response.status_code == 400
    assert "ปีรุ่นเริ่มต้น" in response.json()["detail"]


def test_the_same_cohort_is_fine_in_a_different_program_type(client):
    """คนละกลุ่มหลักสูตรเดินบันไดคนละอัน ปีรุ่นซ้ำกันจึงไม่กำกวม"""
    assert _create_set(client).status_code == 201

    response = _create_set(
        client, code="2570-continuing", program_type="continuing", name="ชุดต่อเนื่อง 2570"
    )

    assert response.status_code == 201


def test_updating_a_set_to_a_taken_cohort_is_rejected(client):
    first = _create_set(client).json()
    _create_set(client, code="2571-regular", effective_from_cohort=2571, name="ชุด 2571")

    response = client.put(
        f"/criteria-sets/{first['id']}",
        json=_set_payload(effective_from_cohort=2571),
        headers=_admin_headers(client),
    )

    assert response.status_code == 400


def test_keeping_its_own_cohort_on_update_is_allowed(client):
    """แก้ชื่อโดยไม่เปลี่ยนปีรุ่น ต้องไม่ไปชนกับตัวเอง"""
    created = _create_set(client).json()

    response = client.put(
        f"/criteria-sets/{created['id']}",
        json=_set_payload(name="แก้แค่ชื่อ"),
        headers=_admin_headers(client),
    )

    assert response.status_code == 200


def test_duplicate_code_is_rejected(client):
    assert _create_set(client).status_code == 201

    response = _create_set(client, effective_from_cohort=2571)

    assert response.status_code == 400
    assert "รหัส" in response.json()["detail"]


# --------------------------- เตือนผลรวมชั่วโมง ---------------------------
def test_new_set_warns_that_hours_do_not_add_up_yet(client):
    """ชุดที่เพิ่งสร้างยังไม่มีรายการเลย ผลรวมจึงเป็น 0 — เตือน ไม่ใช่ห้าม"""
    body = _create_set(client).json()

    assert body["hours_warning"] is not None
    assert "0" in body["hours_warning"]
    assert "60" in body["hours_warning"]


def test_warning_clears_when_the_hours_add_up(client, unit):
    created = _create_set(client, total_required_hours=10).json()
    client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={"name": "รายการ ก", "learning_unit_id": unit.id, "required_hours": 6},
        headers=_admin_headers(client),
    )
    client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={"name": "รายการ ข", "learning_unit_id": unit.id, "required_hours": 4},
        headers=_admin_headers(client),
    )

    body = client.put(
        f"/criteria-sets/{created['id']}",
        json=_set_payload(total_required_hours=10),
        headers=_admin_headers(client),
    ).json()

    assert body["hours_warning"] is None


def test_grouped_requirements_count_once_as_the_group(client, unit):
    """สมาชิกกลุ่มแชร์เป้าถูกนับเป็นก้อนของกลุ่มครั้งเดียว ไม่ใช่บวกทีละตัว

    กฎเดียวกับที่ตัวคำนวณความครบใช้ — ถ้าที่นี่บวกซ้ำ ผู้ดูแลจะโดนเตือนทั้งที่ชุดถูกแล้ว
    """
    created = _create_set(client, total_required_hours=16).json()
    group = client.post(
        f"/criteria-sets/{created['id']}/requirement-groups",
        json={"code": "social-16", "name": "กลุ่ม Social", "required_hours": 16},
        headers=_admin_headers(client),
    ).json()
    for name in ("ด้านนวัตกรรมสังคม", "ด้านผู้ประกอบการ"):
        client.post(
            f"/criteria-sets/{created['id']}/requirements",
            json={
                "name": name,
                "learning_unit_id": unit.id,
                "group_id": group["id"],
                "required_hours": 16,
            },
            headers=_admin_headers(client),
        )

    body = client.put(
        f"/criteria-sets/{created['id']}",
        json=_set_payload(total_required_hours=16),
        headers=_admin_headers(client),
    ).json()

    assert body["hours_warning"] is None, "16+16 ต้องไม่ถูกนับเป็น 32"


# --------------------------- Talent / กลุ่ม / รายการ ---------------------------
def test_talent_crud_inside_a_custom_set(client, session):
    created = _create_set(client).json()
    headers = _admin_headers(client)

    talent = client.post(
        f"/criteria-sets/{created['id']}/talents",
        json={"code": "glocal", "name": "TSU Glocal Talent", "plo": "PLO 1", "sort_order": 1},
        headers=headers,
    )
    assert talent.status_code == 201, talent.text
    talent_id = talent.json()["id"]

    updated = client.put(
        f"/talents/{talent_id}",
        json={"code": "glocal", "name": "Glocal (แก้แล้ว)", "plo": "PLO 1", "sort_order": 2},
        headers=headers,
    )
    assert updated.status_code == 200
    assert updated.json()["name"] == "Glocal (แก้แล้ว)"
    assert updated.json()["sort_order"] == 2

    assert client.delete(f"/talents/{talent_id}", headers=headers).status_code == 204
    assert session.get(Talent, talent_id) is None


def test_duplicate_talent_code_within_a_set_is_rejected(client):
    created = _create_set(client).json()
    headers = _admin_headers(client)
    body = {"code": "glocal", "name": "Glocal"}
    assert client.post(
        f"/criteria-sets/{created['id']}/talents", json=body, headers=headers
    ).status_code == 201

    response = client.post(
        f"/criteria-sets/{created['id']}/talents", json=body, headers=headers
    )

    assert response.status_code == 400


def test_talent_in_use_cannot_be_deleted(client, unit):
    created = _create_set(client).json()
    headers = _admin_headers(client)
    talent = client.post(
        f"/criteria-sets/{created['id']}/talents",
        json={"code": "glocal", "name": "Glocal"},
        headers=headers,
    ).json()
    client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={"name": "รายการในทาเลนต์", "learning_unit_id": unit.id,
              "talent_id": talent["id"], "required_hours": 4},
        headers=headers,
    )

    response = client.delete(f"/talents/{talent['id']}", headers=headers)

    assert response.status_code == 400
    assert "1" in response.json()["detail"]


def test_requirement_crud_inside_a_custom_set(client, session, unit):
    created = _create_set(client).json()
    headers = _admin_headers(client)

    requirement = client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={
            "name": "กิจกรรมปฐมนิเทศนิสิต",
            "learning_unit_id": unit.id,
            "is_mandatory": True,
            "required_hours": 4,
        },
        headers=headers,
    )
    assert requirement.status_code == 201, requirement.text
    requirement_id = requirement.json()["id"]
    assert requirement.json()["is_mandatory"] is True

    updated = client.put(
        f"/requirements/{requirement_id}",
        json={"name": "ปฐมนิเทศ (แก้แล้ว)", "learning_unit_id": unit.id, "required_hours": 6},
        headers=headers,
    )
    assert updated.status_code == 200
    assert updated.json()["required_hours"] == 6
    assert updated.json()["is_mandatory"] is False

    assert client.delete(f"/requirements/{requirement_id}", headers=headers).status_code == 204
    assert session.get(Requirement, requirement_id) is None


def test_requirement_cannot_point_at_a_talent_from_another_set(client, unit):
    first = _create_set(client).json()
    second = _create_set(client, code="2571-regular", effective_from_cohort=2571,
                         name="ชุด 2571").json()
    headers = _admin_headers(client)
    talent = client.post(
        f"/criteria-sets/{second['id']}/talents",
        json={"code": "glocal", "name": "Glocal ของอีกชุด"},
        headers=headers,
    ).json()

    response = client.post(
        f"/criteria-sets/{first['id']}/requirements",
        json={"name": "รายการข้ามชุด", "learning_unit_id": unit.id,
              "talent_id": talent["id"], "required_hours": 4},
        headers=headers,
    )

    assert response.status_code == 400
    assert "คนละชุด" in response.json()["detail"]


def test_requirement_with_an_unknown_learning_unit_is_rejected(client):
    created = _create_set(client).json()

    response = client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={"name": "รายการหน่วยผี", "learning_unit_id": 99999, "required_hours": 4},
        headers=_admin_headers(client),
    )

    assert response.status_code == 400


def test_requirement_group_crud(client, session):
    created = _create_set(client).json()
    headers = _admin_headers(client)

    group = client.post(
        f"/criteria-sets/{created['id']}/requirement-groups",
        json={"code": "social-16", "name": "กลุ่ม Social", "required_hours": 16,
              "rule_note": "เลือกด้านเดียวหรือรวมสองด้าน"},
        headers=headers,
    )
    assert group.status_code == 201, group.text
    group_id = group.json()["id"]

    updated = client.put(
        f"/requirement-groups/{group_id}",
        json={"code": "social-16", "name": "กลุ่ม Social (แก้)", "required_hours": 20},
        headers=headers,
    )
    assert updated.status_code == 200
    assert updated.json()["required_hours"] == 20

    assert client.delete(f"/requirement-groups/{group_id}", headers=headers).status_code == 204
    assert session.get(RequirementGroup, group_id) is None


# --------------------------- สิทธิ์ ---------------------------
def test_every_write_endpoint_is_admin_only(client, session, unit):
    """client ตัวปกติล็อกอินเป็น staff — ทุกทางที่เขียนได้ต้องตอบ 403"""
    created = _create_set(client).json()
    talent = client.post(
        f"/criteria-sets/{created['id']}/talents",
        json={"code": "glocal", "name": "Glocal"},
        headers=_admin_headers(client),
    ).json()
    requirement = client.post(
        f"/criteria-sets/{created['id']}/requirements",
        json={"name": "รายการ", "learning_unit_id": unit.id, "required_hours": 4},
        headers=_admin_headers(client),
    ).json()
    group = client.post(
        f"/criteria-sets/{created['id']}/requirement-groups",
        json={"code": "g1", "name": "กลุ่ม", "required_hours": 8},
        headers=_admin_headers(client),
    ).json()

    assert client.post("/criteria-sets", json=_set_payload(code="x")).status_code == 403
    assert client.put(f"/criteria-sets/{created['id']}", json=_set_payload()).status_code == 403
    assert client.delete(f"/criteria-sets/{created['id']}").status_code == 403
    assert client.post(
        f"/criteria-sets/{created['id']}/talents", json={"code": "a", "name": "a"}
    ).status_code == 403
    assert client.put(
        f"/talents/{talent['id']}", json={"code": "a", "name": "a"}
    ).status_code == 403
    assert client.delete(f"/talents/{talent['id']}").status_code == 403
    assert client.put(
        f"/requirements/{requirement['id']}",
        json={"name": "a", "learning_unit_id": unit.id},
    ).status_code == 403
    assert client.delete(f"/requirements/{requirement['id']}").status_code == 403
    assert client.put(
        f"/requirement-groups/{group['id']}",
        json={"code": "g1", "name": "a", "required_hours": 8},
    ).status_code == 403
    assert client.delete(f"/requirement-groups/{group['id']}").status_code == 403


def test_students_can_still_read_criteria_sets(client, tokens):
    """อ่านได้ทุก role เหมือนเดิม — เฟสนี้เพิ่มแค่ทางเขียน"""
    student_headers = {"Authorization": f"Bearer {tokens['student']}"}

    assert client.get("/criteria-sets", headers=student_headers).status_code == 200


# --------------------------- ฟิลด์ที่หน้าจอต้องใช้ ---------------------------
def test_list_exposes_the_fields_the_admin_screen_needs(client):
    """หน้าจัดการชุดเกณฑ์ต้องรู้ว่าชุดไหนแก้ได้ และใช้กับรุ่นไหน จาก GET ตัวเดียว"""
    created = _create_set(client).json()

    listed = client.get("/criteria-sets").json()
    mine = next(c for c in listed if c["id"] == created["id"])

    assert mine["effective_from_cohort"] == 2570
    assert mine["is_system"] is False
    assert mine["program_type"] == "regular"
    assert mine["counting_rule"] == "min_per_requirement"
    # ชุดที่ยังไม่มีรายการเลย ต้องติดคำเตือนมาให้หน้าจอแสดง
    assert mine["hours_warning"] is not None


def test_system_sets_are_still_flagged_as_official(client, system_set):
    """is_system ยังส่งมาเป็นป้าย "ชุดทางการ" (หน้าจอใช้ซ่อนปุ่มแก้/ลบระดับชุด)"""
    listed = client.get("/criteria-sets").json()
    official = next(c for c in listed if c["id"] == system_set.id)

    assert official["is_system"] is True


def test_learning_units_are_listed_for_the_requirement_form(client, unit):
    """ฟอร์มรายการเกณฑ์ต้องเลือกหน่วยการเรียนรู้ได้ จึงต้องมีทางอ่านรายการหน่วย"""
    response = client.get("/learning-units")

    assert response.status_code == 200
    body = response.json()
    assert any(u["id"] == unit.id and u["name"] == unit.name for u in body)
    # เรียงตามรหัสหน่วย เพื่อให้ลำดับใน dropdown คงที่ทุกครั้ง
    codes = [u["code"] for u in body]
    assert codes == sorted(codes)


def test_learning_units_require_login(client):
    assert client.get(
        "/learning-units", headers={"Authorization": "Bearer not-a-token"}
    ).status_code == 401


# --------------------------- กฎกลุ่มแชร์เป้าที่สร้างผ่าน UI ---------------------------
def _build_social_set_through_the_api(client, unit):
    """ทำตามลำดับเดียวกับที่ผู้ดูแลกดในหน้าจอ: สร้างชุด → เพิ่มกลุ่ม → เพิ่มรายการ →
    เปิดฟอร์มแก้ไขแล้วเลือกกลุ่ม (PUT) — คืน (ชุด, กลุ่ม, id รายการ 2 ตัว)"""
    headers = _admin_headers(client)
    created = _create_set(client, total_required_hours=16).json()
    group = client.post(
        f"/criteria-sets/{created['id']}/requirement-groups",
        json={"code": "social-16", "name": "กลุ่ม Social", "required_hours": 16},
        headers=headers,
    ).json()

    requirement_ids = []
    for name in ("ด้านนวัตกรรมสังคม", "ด้านผู้ประกอบการ"):
        response = client.post(
            f"/criteria-sets/{created['id']}/requirements",
            json={"name": name, "learning_unit_id": unit.id, "required_hours": 16},
            headers=headers,
        )
        assert response.status_code == 201, response.text
        requirement_ids.append(response.json()["id"])

    # ก่อนผูก: กลุ่มยังไม่มีสมาชิก แต่ต้องโผล่ใน GET แล้ว ไม่งั้นฟอร์มไม่มีตัวเลือกให้เลือก
    listed = next(c for c in client.get("/criteria-sets").json() if c["id"] == created["id"])
    assert [g["id"] for g in listed["requirement_groups"]] == [group["id"]]
    assert all(r["group_id"] is None for g in listed["groups"] for r in g["requirements"])

    for requirement_id, name in zip(requirement_ids, ("ด้านนวัตกรรมสังคม", "ด้านผู้ประกอบการ")):
        response = client.put(
            f"/requirements/{requirement_id}",
            json={
                "name": name,
                "learning_unit_id": unit.id,
                "group_id": group["id"],
                "required_hours": 16,
            },
            headers=headers,
        )
        assert response.status_code == 200, response.text

    return created, group, requirement_ids


def test_requirement_read_exposes_group_id_and_set_lists_its_groups(client, unit):
    created, group, requirement_ids = _build_social_set_through_the_api(client, unit)

    listed = next(c for c in client.get("/criteria-sets").json() if c["id"] == created["id"])
    requirements = [r for g in listed["groups"] for r in g["requirements"]]

    assert sorted(r["id"] for r in requirements) == sorted(requirement_ids)
    assert all(r["group_id"] == group["id"] for r in requirements)
    assert all(r["group_name"] == "กลุ่ม Social" for r in requirements)
    assert listed["requirement_groups"] == [
        {
            "id": group["id"],
            "criteria_set_id": created["id"],
            "code": "social-16",
            "name": "กลุ่ม Social",
            "required_hours": 16.0,
            "rule_note": None,
        }
    ]
    assert listed["hours_warning"] is None, "สองรายการในกลุ่มนับเป็นก้อน 16 ครั้งเดียว"


def test_list_returns_every_field_a_full_row_put_would_overwrite(client, unit, system_set, session):
    """PUT /requirements แทนที่ทั้งแถว — GET ต้องส่ง rule_note / organizer / min_activities มาด้วย

    ไม่งั้นฟอร์มแก้ไขไม่มีค่าเดิมส่งกลับ แก้ชั่วโมงรายการ Social ในชุด 2567 ครั้งเดียว
    "กฎพิเศษ ≥ 16" ก็หายไปเงียบ ๆ (ชุดทางการแก้ได้แล้ว จุดนี้จึงเกิดได้จริง)
    """
    session.add(
        Requirement(
            criteria_set_id=system_set.id,
            name="ด้านการสร้างนวัตกรรมสังคม",
            learning_unit_id=unit.id,
            required_hours=16,
            rule_note="กฎพิเศษ: สองด้านรวมกัน ≥ 16",
            organizer="กองกิจการนิสิต",
            min_activities=2,
        )
    )
    session.commit()

    listed = next(c for c in client.get("/criteria-sets").json() if c["id"] == system_set.id)
    item = next(r for g in listed["groups"] for r in g["requirements"])

    assert item["rule_note"] == "กฎพิเศษ: สองด้านรวมกัน ≥ 16"
    assert item["organizer"] == "กองกิจการนิสิต"
    assert item["min_activities"] == 2


def test_requirement_groups_do_not_leak_across_sets(client, unit, system_set, session):
    session.add(
        RequirementGroup(
            criteria_set_id=system_set.id, code="social-16", name="Social ทางการ", required_hours=16
        )
    )
    session.commit()
    created, group, _ = _build_social_set_through_the_api(client, unit)

    listed = {c["id"]: c for c in client.get("/criteria-sets").json()}

    assert [g["id"] for g in listed[created["id"]]["requirement_groups"]] == [group["id"]]
    assert [g["name"] for g in listed[system_set.id]["requirement_groups"]] == ["Social ทางการ"]


@pytest.mark.parametrize(
    ("innovation", "entrepreneur", "completed"),
    [(8, 8, True), (16, 0, True), (12, 4, True), (8, 4, False), (0, 12, False)],
)
def test_group_built_through_the_api_enforces_the_combined_target(
    client, session, unit, innovation, entrepreneur, completed
):
    """หัวใจของการปิดช่องว่าง: กฎ "สองด้านรวม ≥ 16" ที่ผู้ดูแลสร้างเองผ่าน UI ต้องตัดสิน
    ความครบแบบเดียวกับกลุ่ม Social ทางการ — รวมยอดทั้งกลุ่ม ไม่ใช่ต้องครบทีละด้าน"""
    from datetime import datetime

    from sqlalchemy import text

    from app.completion import progress_by_student
    from app.gold import create_gold_layer
    from app.models import (
        Activity,
        ApprovalStatus,
        EvidenceStatus,
        Participation,
        User,
        UserRole,
    )

    created, group, requirement_ids = _build_social_set_through_the_api(client, unit)
    student = Student(
        student_id="7000000001",
        full_name="นิสิต 70",
        faculty="คณะทดสอบ",
        major="ไม่ระบุ",
        year_level=1,
        criteria_set_id=created["id"],
    )
    session.add(student)
    session.commit()

    staff_id = session.exec(select(User).where(User.role == UserRole.staff)).first().id
    for requirement_id, hours in zip(requirement_ids, (innovation, entrepreneur)):
        if not hours:
            continue
        activity = Activity(
            name=f"กิจกรรมรายการ {requirement_id}",
            activity_type="วิชาการ",
            max_participants=100,
            start_at=datetime(2026, 7, 1, 9),
            location="อาคารเรียนรวม 1",
            hours=hours,
            created_by=staff_id,
            approval_status=ApprovalStatus.approved,
        )
        session.add(activity)
        session.flush()
        session.add(ActivityRequirement(activity_id=activity.id, requirement_id=requirement_id))
        session.add(
            Participation(
                student_id=student.id,
                activity_id=activity.id,
                evidence_status=EvidenceStatus.approved,
                hours_earned=hours,
            )
        )
    session.commit()

    create_gold_layer(session)
    rows = session.execute(
        text(
            "SELECT category_key, category_name, required_hours, earned_hours, item_kind "
            "FROM gold_student_hours WHERE student_key = :sid"
        ),
        {"sid": student.id},
    ).mappings().all()

    # สองรายการในกลุ่มถูกวัดเป็นรายการเดียวของกลุ่ม ไม่ใช่สองรายการ 16 ชม.
    assert [(r["item_kind"], r["category_name"], r["required_hours"]) for r in rows] == [
        ("group", "กลุ่ม Social", 16)
    ]
    progress = progress_by_student(
        (student.id, r["category_key"], r["category_name"], r["required_hours"], r["earned_hours"])
        for r in rows
    )[student.id]
    assert progress.completed is completed
    assert progress.items[0].earned_hours == innovation + entrepreneur


def test_unknown_set_returns_404(client):
    assert client.delete("/criteria-sets/99999", headers=_admin_headers(client)).status_code == 404
    assert client.put(
        "/criteria-sets/99999", json=_set_payload(), headers=_admin_headers(client)
    ).status_code == 404


def test_extra_fields_are_rejected(client):
    """กันยัดฟิลด์ที่ระบบเป็นเจ้าของ เช่น is_system"""
    response = client.post(
        "/criteria-sets",
        json=_set_payload(is_system=True),
        headers=_admin_headers(client),
    )

    assert response.status_code == 422
