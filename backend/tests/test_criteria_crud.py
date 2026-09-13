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


# --------------------------- กันแก้ชุดของระบบ ---------------------------
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


def test_contents_of_a_system_set_are_protected_too(client, session, system_set, unit):
    """แก้ Talent/รายการข้างในชุดทางการก็คือแก้เกณฑ์ทางการ — ต้องกันเหมือนกัน

    ถ้าปล่อยให้แก้ ผลจะแย่กว่าเดิม: seed จะเขียนทับกลับตอนบูตครั้งถัดไป
    ผู้ดูแลจึงเจอ "แก้ได้แต่ไม่อยู่" ซึ่งหาสาเหตุยากกว่าโดนห้ามไปเลย
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
    assert client.post(
        f"/criteria-sets/{system_set.id}/talents",
        json={"code": "new", "name": "เพิ่มใหม่"},
        headers=headers,
    ).status_code == 403
    assert client.put(
        f"/talents/{talent.id}",
        json={"code": "glocal", "name": "แก้ชื่อ", "sort_order": 0},
        headers=headers,
    ).status_code == 403
    assert client.delete(f"/talents/{talent.id}", headers=headers).status_code == 403
    assert client.put(
        f"/requirement-groups/{group.id}",
        json={"code": "social-16", "name": "แก้ชื่อกลุ่ม", "required_hours": 20},
        headers=headers,
    ).status_code == 403
    assert client.delete(f"/requirement-groups/{group.id}", headers=headers).status_code == 403
    assert client.put(
        f"/requirements/{requirement.id}",
        json={"name": "แก้ชื่อรายการ", "learning_unit_id": unit.id, "required_hours": 4},
        headers=headers,
    ).status_code == 403
    assert client.delete(f"/requirements/{requirement.id}", headers=headers).status_code == 403


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
