"""GET /criteria-sets + กิจกรรมที่สร้างผ่าน UI ต้องนับชั่วโมงให้นิสิตชุดเกณฑ์ 2567 จริง

ฟอร์มกิจกรรมเลือก ``requirement_ids`` จากรายการที่ endpoint นี้ส่งไป เทสต์จึงคุมทั้งรูป
คำตอบ (จัดกลุ่มตามชุดเกณฑ์) และเส้นทางปลายทาง: เลือกแล้วชั่วโมงเข้ารายการนั้นของนิสิตจริง
"""

from datetime import datetime

import pytest
from sqlalchemy import text
from sqlmodel import select

from app.gold import create_gold_layer
from app.models import (
    ActivityRequirement,
    CriteriaSet,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    Requirement,
    Student,
)
from seed_criteria import populate as seed_criteria

FUTURE = datetime(2027, 3, 1, 9, 0)

# ชุด legacy ถูกแปลงมาจากหมวดชั่วโมงเดิมที่อยู่ในฐาน — ไม่มีหมวดเดิมก็ไม่มีชุด legacy
# ชื่อหมวดตรงกับหน่วยการเรียนรู้ 1 และ 3 ตามตารางแปลงใน seed_criteria
LEGACY_CATEGORIES = [
    ("พัฒนาทักษะชีวิต", 12.0, [("กิจกรรมเสริมสร้างคุณค่าแห่งตน", 8.0), ("กิจกรรมบูรณาการ 1", 4.0)]),
    ("ศิลปวัฒนธรรมอาเซียน", 6.0, [("กิจกรรมศิลปวัฒนธรรม", 6.0)]),
]


@pytest.fixture
def criteria(session):
    for name, hours, subs in LEGACY_CATEGORIES:
        category = HourCategory(name=name, required_hours=hours)
        session.add(category)
        session.commit()
        for sub_name, sub_hours in subs:
            session.add(
                HourSubcategory(
                    category_id=category.id, name=sub_name, required_hours=sub_hours
                )
            )
        session.commit()
    seed_criteria(session)
    session.commit()
    return session.exec(select(CriteriaSet).where(CriteriaSet.code == "2567-regular")).one()


def _sets_by_code(client) -> dict:
    response = client.get("/criteria-sets")
    assert response.status_code == 200, response.text
    return {s["code"]: s for s in response.json()}


def _student_2567(session, criteria, code="6900000009"):
    student = Student(
        student_id=code,
        full_name=f"นิสิต {code}",
        faculty="คณะทดสอบ",
        major="ไม่ระบุ",
        year_level=1,
        criteria_set_id=criteria.id,
    )
    session.add(student)
    session.commit()
    return student


def _requirement(session, criteria, name):
    return session.exec(
        select(Requirement).where(
            Requirement.criteria_set_id == criteria.id, Requirement.name == name
        )
    ).one()


def _earned(session, student_id, item_key) -> float:
    create_gold_layer(session)
    row = session.execute(
        text(
            "SELECT earned_hours FROM gold_student_hours "
            "WHERE student_key = :sid AND category_key = :item"
        ),
        {"sid": student_id, "item": item_key},
    ).first()
    return float(row[0] or 0) if row else 0.0


def _join(session, student, activity_id, hours):
    session.add(
        Participation(
            student_id=student.id,
            activity_id=activity_id,
            evidence_status=EvidenceStatus.approved,
            hours_earned=hours,
        )
    )
    session.commit()


# ------------------------------------------------------------------ รูปคำตอบ

def test_criteria_sets_group_2567_by_talent_and_legacy_by_learning_unit(client, criteria):
    sets = _sets_by_code(client)
    assert set(sets) == {"2567-regular", "legacy-2566"}

    new = sets["2567-regular"]
    assert new["grouped_by"] == "talent"
    assert new["academic_year"] == 2567 and new["total_required_hours"] == 60
    assert [g["subtitle"] for g in new["groups"]] == ["PLO 1", "PLO 2", "PLO 3"]
    assert all(g["key"].startswith("talent:") for g in new["groups"])
    assert all(g["requirements"] for g in new["groups"])

    old = sets["legacy-2566"]
    assert old["grouped_by"] == "learning_unit"
    # หนึ่งกลุ่มต่อหนึ่งหน่วยการเรียนรู้ที่มีรายการอยู่จริง เรียงตามรหัสหน่วย
    assert [(g["name"], g["subtitle"]) for g in old["groups"]] == [
        ("พัฒนาทักษะชีวิต", "หน่วยที่ 1"),
        ("ศิลปวัฒนธรรมอาเซียน", "หน่วยที่ 3"),
    ]
    assert [r["name"] for r in old["groups"][0]["requirements"]] == [
        "กิจกรรมเสริมสร้างคุณค่าแห่งตน",
        "กิจกรรมบูรณาการ 1",
    ]


def test_every_requirement_appears_exactly_once_with_its_flags(session, client, criteria):
    sets = _sets_by_code(client)
    for criteria_set in sets.values():
        listed = [r["id"] for g in criteria_set["groups"] for r in g["requirements"]]
        in_db = session.exec(
            select(Requirement.id).where(Requirement.criteria_set_id == criteria_set["id"])
        ).all()
        assert sorted(listed) == sorted(in_db), criteria_set["code"]
        assert len(listed) == len(set(listed)), "รายการเดียวห้ามโผล่สองกลุ่ม"

    by_name = {r["name"]: r for g in sets["2567-regular"]["groups"] for r in g["requirements"]}
    orientation = by_name["กิจกรรมปฐมนิเทศนิสิต"]
    assert orientation["is_mandatory"] is True
    assert orientation["required_hours"] == 4
    assert orientation["group_name"] is None
    assert orientation["learning_unit_name"]

    # สองด้านของ Social ใช้เป้าชั่วโมงร่วมกัน — ฟอร์มต้องบอกผู้ใช้ได้
    social = by_name["ด้านการสร้างนวัตกรรมสังคม"]
    assert social["group_name"] and social["is_mandatory"] is False


def test_criteria_sets_need_a_login(client):
    client.headers.pop("Authorization")
    assert client.get("/criteria-sets").status_code == 401


def test_no_criteria_seeded_returns_empty_list(client):
    assert client.get("/criteria-sets").json() == []


# ------------------------------------------------- กิจกรรมที่สร้างผ่าน UI นับให้จริง

def _create_activity(client, requirement_ids, hours=4, **extra):
    body = {
        "name": "อบรมทักษะดิจิทัล 2567",
        "activity_type": "อบรม",
        "hours": hours,
        "max_participants": 50,
        "start_at": FUTURE.isoformat(),
        "location": "อาคารเรียนรวม 1",
        "requirement_ids": requirement_ids,
        **extra,
    }
    return client.post("/activities", json=body)


def test_activity_created_with_requirement_ids_counts_for_a_2567_student(
    session, client, criteria
):
    requirement = _requirement(session, criteria, "ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล")

    response = _create_activity(client, [requirement.id])
    assert response.status_code == 201, response.text
    created = response.json()
    assert created["requirement_ids"] == [requirement.id]
    # ฟอร์มไม่ต้องเลือกหมวดชั่วโมงโครงเดิมอีกแล้วเมื่อเลือกรายการเกณฑ์
    assert created["subcategory_id"] is None

    student = _student_2567(session, criteria)
    _join(session, student, created["id"], 4)

    assert _earned(session, student.id, requirement.id) == 4


def test_activity_can_count_toward_several_requirements_at_once(session, client, criteria):
    requirements = [
        _requirement(session, criteria, name)
        for name in ["การคิด วิจารณญาณ และการแก้ปัญหา", "การบริหารจัดการตนเอง"]
    ]

    created = _create_activity(client, [r.id for r in requirements], hours=3).json()
    student = _student_2567(session, criteria)
    _join(session, student, created["id"], 3)

    # นับเต็มชั่วโมงให้ทุกรายการที่ผูกไว้
    for requirement in requirements:
        assert _earned(session, student.id, requirement.id) == 3


def test_editing_an_activity_replaces_its_requirement_links(session, client, criteria):
    first, second = session.exec(
        select(Requirement)
        .where(Requirement.criteria_set_id == criteria.id)
        .order_by(Requirement.id)
        .limit(2)
    ).all()

    created = _create_activity(client, [first.id]).json()
    response = client.put(
        f"/activities/{created['id']}",
        json={"requirement_ids": [second.id]},
    )
    assert response.status_code == 200, response.text
    assert response.json()["requirement_ids"] == [second.id]

    student = _student_2567(session, criteria)
    _join(session, student, created["id"], 4)

    assert _earned(session, student.id, first.id) == 0
    assert _earned(session, student.id, second.id) == 4


def test_unknown_requirement_id_is_rejected(client, criteria):
    response = _create_activity(client, [9999])
    assert response.status_code == 400
    assert "9999" in response.json()["detail"]


def test_activity_without_any_classification_is_rejected(client, criteria):
    response = _create_activity(client, [])
    assert response.status_code == 422


def test_activity_with_requirement_links_can_still_be_deleted(session, client, criteria):
    """ยังไม่มีใครเข้าร่วม = ลบได้จริง — ตารางเชื่อมรายการเกณฑ์ต้องไม่ค้างขวาง FK"""
    requirement = _requirement(session, criteria, "การบริหารจัดการตนเอง")
    created = _create_activity(client, [requirement.id]).json()

    assert client.delete(f"/activities/{created['id']}").status_code == 204
    assert client.get(f"/activities/{created['id']}").status_code == 404
    assert (
        session.exec(
            select(ActivityRequirement).where(
                ActivityRequirement.activity_id == created["id"]
            )
        ).all()
        == []
    )
