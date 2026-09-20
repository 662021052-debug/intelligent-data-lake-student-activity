"""เฟส 6: ความครบเกณฑ์เทียบกับชุดเกณฑ์ของนิสิตแต่ละคน

คุม: ครบ / ขาดรายการเลือก / ขาดรายการบังคับ (ชั่วโมงรวมถึง 60 ก็ยังไม่ผ่าน) · กฎ Social สองด้าน
รวม ≥ 16 · ชุด legacy นับยอดรวมต่อหน่วย · และทุกผู้อ่าน (แดชบอร์ด อีเมล หน้านิสิต แชตบอต
สคริปต์ตรวจ) ตัดสินผ่าน/ไม่ผ่านตรงกัน
"""

from datetime import datetime, timedelta

import pytest
from sqlalchemy import text
from sqlmodel import select

from app.auth import hash_password
from app.chatbot_sql import Intent, answer_missing, recommend_by_missing_categories
from app.completion import progress_by_student
from app.gold import create_gold_layer
from app.models import (
    Activity,
    ActivityRequirement,
    ApprovalStatus,
    CriteriaSet,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    ImportedCompletion,
    Participation,
    Requirement,
    RequirementGroup,
    Student,
    User,
    UserRole,
)
from app.notifications import collect_at_risk_students
from app.timeutil import now_th_naive
from check_completion import compare
from seed_criteria import populate as seed_criteria

PAST = datetime(2026, 7, 1, 9)
SOCIAL = ("ด้านการสร้างนวัตกรรมสังคม", "ด้านการเป็นผู้ประกอบการ")
ORIENTATION = "กิจกรรมปฐมนิเทศนิสิต"
ELECTIVE = "การบริหารจัดการตนเอง"

# ชั่วโมงที่ทำให้ครบชุด 2567-regular พอดี (Social ด้านละ 8)
FULL = {
    ORIENTATION: 4,
    "กิจกรรมเกี่ยวกับการใช้ชีวิตในมหาวิทยาลัย": 4,
    "การคิด วิจารณญาณ และการแก้ปัญหา": 3,
    ELECTIVE: 3,
    "การทำงานร่วมกับผู้อื่น": 3,
    "ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล": 3,
    "กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์/สิ่งแวดล้อม)": 10,
    "ทักษะการใช้ภาษาเพื่อการสื่อสารในชีวิตประจำวัน": 10,
    "แนวคิดการเป็นนักนวัตกรรมสังคม/ผู้ประกอบการ": 4,
    SOCIAL[0]: 8,
    SOCIAL[1]: 8,
}


@pytest.fixture
def criteria(session):
    seed_criteria(session)
    session.commit()
    return session.exec(select(CriteriaSet).where(CriteriaSet.code == "2567-regular")).one()


def _req(session, name, criteria_set=None):
    query = select(Requirement).where(Requirement.name == name)
    if criteria_set is not None:
        query = query.where(Requirement.criteria_set_id == criteria_set.id)
    return session.exec(query).one()


def _staff_id(session):
    return session.exec(select(User).where(User.role == UserRole.staff)).first().id


def _student(session, criteria_set, code, faculty="คณะทดสอบ", completion=None):
    student = Student(
        student_id=code,
        full_name=f"นิสิต {code}",
        faculty=faculty,
        major="ไม่ระบุ",
        year_level=1,
        criteria_set_id=criteria_set.id if criteria_set else None,
        imported_completion=completion,
    )
    session.add(student)
    session.commit()
    return student


def _activity(session, requirements, hours, *, start_at=PAST, subcategory_id=None, name=None):
    activity = Activity(
        name=name or f"กิจกรรม {len(session.exec(select(Activity)).all()) + 1}",
        activity_type="วิชาการ",
        max_participants=500,
        start_at=start_at,
        location="อาคารเรียนรวม 1",
        hours=hours,
        subcategory_id=subcategory_id,
        created_by=_staff_id(session),
        approval_status=ApprovalStatus.approved,
    )
    session.add(activity)
    session.flush()
    for requirement in requirements:
        session.add(ActivityRequirement(activity_id=activity.id, requirement_id=requirement.id))
    session.commit()
    return activity


def _join(session, student, activity, status=EvidenceStatus.approved):
    session.add(
        Participation(
            student_id=student.id,
            activity_id=activity.id,
            evidence_status=status,
            hours_earned=activity.hours if status == EvidenceStatus.approved else 0,
        )
    )
    session.commit()


def _give(session, student, hours_by_name):
    for name, hours in hours_by_name.items():
        if hours:
            _join(session, student, _activity(session, [_req(session, name)], hours))


def _rows(session, student):
    create_gold_layer(session)
    return session.execute(
        text(
            "SELECT category_key, category_name, required_hours, earned_hours, completed, "
            "item_kind, is_mandatory FROM gold_student_hours WHERE student_key = :sid "
            "ORDER BY category_key"
        ),
        {"sid": student.id},
    ).mappings().all()


def _progress(session, student):
    rows = _rows(session, student)
    return progress_by_student(
        (student.id, r["category_key"], r["category_name"], r["required_hours"], r["earned_hours"])
        for r in rows
    )[student.id]


# ------------------------------------------------------------------ schema / seed

def test_social_pair_is_one_group_of_16_hours(session, criteria):
    group = session.exec(select(RequirementGroup)).one()
    assert (group.criteria_set_id, group.code, group.required_hours) == (criteria.id, "social-16", 16)
    for name in SOCIAL:
        assert _req(session, name).group_id == group.id
    assert _req(session, ORIENTATION).group_id is None

    seed_criteria(session)  # รันซ้ำไม่สร้างกลุ่มซ้ำ
    session.commit()
    assert len(session.exec(select(RequirementGroup)).all()) == 1


def test_2567_student_is_measured_on_ten_items_totalling_60_hours(session, criteria):
    student = _student(session, criteria, "6900000001")
    rows = _rows(session, student)

    assert len(rows) == 10  # 9 รายการเดี่ยว + กลุ่ม Social หนึ่งรายการ
    assert sum(r["required_hours"] for r in rows) == 60
    assert sum(r["required_hours"] for r in rows if r["is_mandatory"]) == 12
    group = [r for r in rows if r["item_kind"] == "group"]
    assert len(group) == 1 and group[0]["required_hours"] == 16
    assert all(r["earned_hours"] == 0 and r["completed"] == 0 for r in rows)


# ------------------------------------------------------------------ ปลดล็อกชุด 2567

def _admin_headers(client):
    response = client.post("/auth/login", data={"username": "admin", "password": "admin123"})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _requirement_payload(requirement, **overrides):
    payload = {
        "name": requirement.name,
        "learning_unit_id": requirement.learning_unit_id,
        "talent_id": requirement.talent_id,
        "group_id": requirement.group_id,
        "is_mandatory": requirement.is_mandatory,
        "required_hours": requirement.required_hours,
        "min_activities": requirement.min_activities,
        "rule_note": requirement.rule_note,
        "organizer": requirement.organizer,
    }
    payload.update(overrides)
    return payload


def test_reseed_and_a_no_change_save_keep_every_verdict_identical(client, session, criteria):
    """regression: บูตใหม่ (รัน seed) + ผู้ดูแลกดบันทึกฟอร์มโดยไม่เปลี่ยนค่า → ผลตัดสินนิสิตต้องเหมือนเดิมทุกตัวเลข"""
    complete = _student(session, criteria, "6900000031")
    _give(session, complete, FULL)
    partial = _student(session, criteria, "6900000032")
    _give(session, partial, {**FULL, ELECTIVE: 0})

    def verdicts():
        result = {}
        for student in (complete, partial):
            p = _progress(session, student)
            result[student.id] = (p.completed, p.counted_hours, p.required_hours, [g.name for g in p.gaps])
        return result

    before = verdicts()
    assert before[complete.id][0] is True and before[partial.id][0] is False

    seed_criteria(session)
    session.commit()
    for name in (ELECTIVE, ORIENTATION, SOCIAL[0]):
        requirement = _req(session, name)
        response = client.put(
            f"/requirements/{requirement.id}",
            json=_requirement_payload(requirement),
            headers=_admin_headers(client),
        )
        assert response.status_code == 200, response.text
    session.expire_all()

    assert verdicts() == before


def test_admin_edit_to_2567_survives_reseed_and_is_what_students_are_measured_on(client, session, criteria):
    """แก้ชุด 2567 ผ่าน API → รัน seed ซ้ำ (restart) ค่ายังอยู่ และใช้วัดนิสิตทันที (gold คำนวณสดจากโครง)"""
    student = _student(session, criteria, "6900000033")
    _give(session, student, FULL)
    assert _progress(session, student).completed

    elective = _req(session, ELECTIVE)
    response = client.put(
        f"/requirements/{elective.id}",
        json=_requirement_payload(elective, required_hours=5),
        headers=_admin_headers(client),
    )
    assert response.status_code == 200, response.text

    seed_criteria(session)
    session.commit()
    session.expire_all()

    assert _req(session, ELECTIVE).required_hours == 5, "seed ต้องไม่ดึงกลับเป็น 3"
    p = _progress(session, student)
    assert not p.completed
    assert [g.name for g in p.gaps] == [ELECTIVE]


# ------------------------------------------------------------------ three cases

def test_complete_student_passes(session, criteria):
    student = _student(session, criteria, "6900000001")
    _give(session, student, FULL)

    p = _progress(session, student)
    assert p.completed
    assert (p.counted_hours, p.required_hours, p.percent) == (60, 60, 100)


def test_missing_an_elective_fails(session, criteria):
    student = _student(session, criteria, "6900000002")
    _give(session, student, {**FULL, ELECTIVE: 0})

    p = _progress(session, student)
    assert not p.completed
    assert [g.name for g in p.gaps] == [ELECTIVE]
    assert p.counted_hours == 57


def test_missing_a_mandatory_fails_even_with_60_hours(session, criteria):
    """เดิมแดชบอร์ดตัดสินจากชั่วโมงรวม ≥ 60 — คนนี้ได้ 60 แต่ขาดปฐมนิเทศซึ่งเป็นรายการบังคับ."""
    student = _student(session, criteria, "6900000003")
    tsu_good = "กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์/สิ่งแวดล้อม)"
    _give(session, student, {**FULL, ORIENTATION: 0, tsu_good: 14})

    p = _progress(session, student)
    total = session.execute(
        text("SELECT SUM(hours_earned) FROM participation WHERE student_id = :sid"),
        {"sid": student.id},
    ).scalar()
    assert total == 60
    assert not p.completed
    assert [g.name for g in p.gaps] == [ORIENTATION]
    assert p.counted_hours == 56  # ชั่วโมงเกินของ TSU Good ไม่ชดเชยปฐมนิเทศ


# ------------------------------------------------------------------ Social rule

@pytest.mark.parametrize(
    ("innovation", "entrepreneur", "completed"),
    [(8, 8, True), (16, 0, True), (0, 16, True), (12, 4, True), (20, 0, True), (8, 4, False), (0, 12, False)],
)
def test_social_sides_count_together_toward_16(session, criteria, innovation, entrepreneur, completed):
    student = _student(session, criteria, "6900000004")
    _give(session, student, {**FULL, SOCIAL[0]: innovation, SOCIAL[1]: entrepreneur})

    p = _progress(session, student)
    assert p.completed is completed
    social = next(i for i in p.items if i.name.startswith("ด้านนวัตกรรมสังคม"))
    assert social.earned_hours == innovation + entrepreneur


def test_an_activity_linked_to_both_social_sides_counts_once(session, criteria):
    student = _student(session, criteria, "6900000005")
    _give(session, student, {**FULL, SOCIAL[0]: 0, SOCIAL[1]: 0})
    both = _activity(session, [_req(session, SOCIAL[0]), _req(session, SOCIAL[1])], 8)
    _join(session, student, both)

    social = next(i for i in _progress(session, student).items if i.name.startswith("ด้านนวัตกรรมสังคม"))
    assert social.earned_hours == 8  # ไม่ใช่ 16 จากการนับซ้ำสองด้าน


def test_an_activity_linked_to_two_items_counts_for_each(session, criteria):
    student = _student(session, criteria, "6900000006")
    shared = _activity(
        session, [_req(session, ELECTIVE), _req(session, "การทำงานร่วมกับผู้อื่น")], 3
    )
    _join(session, student, shared)

    earned = {i.name: i.earned_hours for i in _progress(session, student).items}
    assert earned[ELECTIVE] == 3
    assert earned["การทำงานร่วมกับผู้อื่น"] == 3


def test_only_approved_hours_in_the_students_own_set_count(session, criteria):
    student = _student(session, criteria, "6900000007")
    _join(session, student, _activity(session, [_req(session, ORIENTATION)], 4), EvidenceStatus.pending)
    legacy_only = HourCategory(name="พัฒนาทักษะชีวิต", required_hours=12)
    session.add(legacy_only)
    session.commit()
    sub = HourSubcategory(category_id=legacy_only.id, name="หมวดย่อยที่ไม่มีในชุด 2567", required_hours=12)
    session.add(sub)
    session.commit()
    _join(session, student, _activity(session, [], 6, subcategory_id=sub.id))

    assert _progress(session, student).counted_hours == 0


# ------------------------------------------------------------------ legacy + no set

def _legacy_world(session):
    category = HourCategory(name="พัฒนาทักษะชีวิต", required_hours=12)
    session.add(category)
    session.commit()
    subs = [
        HourSubcategory(category_id=category.id, name="กิจกรรมเสริมสร้างคุณค่าแห่งตน", required_hours=8),
        HourSubcategory(category_id=category.id, name="กิจกรรมบูรณาการ 1", required_hours=4),
    ]
    session.add_all(subs)
    session.commit()
    seed_criteria(session)
    session.commit()
    legacy = session.exec(select(CriteriaSet).where(CriteriaSet.code == "legacy-2566")).one()
    return legacy, subs


def test_legacy_set_counts_the_unit_total_and_old_style_activities(session, criteria):
    legacy, subs = _legacy_world(session)
    student = _student(session, legacy, "6500000001")
    # กิจกรรมโครงเดิม: มีแต่ subcategory_id ไม่ได้ผูก requirement — นับผ่านชื่อหมวดย่อย
    _join(session, student, _activity(session, [], 12, subcategory_id=subs[0].id))

    rows = _rows(session, student)
    assert [(r["item_kind"], r["category_name"], r["required_hours"]) for r in rows] == [
        ("unit", "พัฒนาทักษะชีวิต", 12)
    ]
    # total_per_unit: 12 ชม. ในหมวดย่อยเดียวครบทั้งหน่วยได้ (เหมือนหมวดชั่วโมงเดิม)
    assert rows[0]["earned_hours"] == 12 and rows[0]["completed"] == 1


def test_legacy_is_edited_through_the_same_crud_and_the_edit_is_what_old_students_are_measured_on(
    client, session, criteria
):
    """เกณฑ์เดิมแก้ผ่าน /requirements ตัวเดียวกับ 2567 (หน้าหมวดชั่วโมงเลิกแก้ /hour-categories แล้ว)

    กดบันทึกโดยไม่เปลี่ยนค่า → ผลตัดสินเหมือนเดิมทุกตัวเลข · แก้ชั่วโมง → รัน seed ซ้ำ (restart)
    ค่ายังอยู่ และหน่วยนั้นของนิสิตรุ่นเก่าถูกวัดด้วยค่าใหม่ทันที
    """
    legacy, subs = _legacy_world(session)
    student = _student(session, legacy, "6500000002")
    _join(session, student, _activity(session, [], 12, subcategory_id=subs[0].id))
    headers = _admin_headers(client)

    def unit_row():
        rows = _rows(session, student)
        return [(r["category_name"], r["required_hours"], r["earned_hours"], r["completed"]) for r in rows]

    before = unit_row()
    assert before == [("พัฒนาทักษะชีวิต", 12, 12, 1)]

    item = _req(session, "กิจกรรมบูรณาการ 1", legacy)
    unchanged = client.put(f"/requirements/{item.id}", json=_requirement_payload(item), headers=headers)
    assert unchanged.status_code == 200, unchanged.text
    session.expire_all()
    assert unit_row() == before

    edited = client.put(
        f"/requirements/{item.id}", json=_requirement_payload(item, required_hours=10), headers=headers
    )
    assert edited.status_code == 200, edited.text
    seed_criteria(session)
    session.commit()
    session.expire_all()

    assert _req(session, "กิจกรรมบูรณาการ 1", legacy).required_hours == 10, "seed ต้องไม่ดึงกลับเป็น 4"
    # total_per_unit: เป้าของหน่วย = ผลรวมรายการในหน่วย 8 + 10 = 18 · ได้ 12 → ยังไม่ครบ
    assert unit_row() == [("พัฒนาทักษะชีวิต", 18, 12, 0)]


def test_student_without_a_criteria_set_keeps_the_old_hour_categories(session):
    category = HourCategory(name="หมวดเดียว", required_hours=10)
    session.add(category)
    session.commit()
    sub = HourSubcategory(category_id=category.id, name="ย่อยเดียว", required_hours=10)
    session.add(sub)
    session.commit()
    student = _student(session, None, "70001")
    _join(session, student, _activity(session, [], 10, subcategory_id=sub.id))

    rows = _rows(session, student)
    assert [(r["category_key"], r["item_kind"], r["earned_hours"], r["completed"]) for r in rows] == [
        (category.id, "category", 10, 1)
    ]


# ------------------------------------------------------------------ readers agree

@pytest.fixture
def cohort(session, criteria):
    """ครบ 1 · ขาดเลือก 1 · ขาดบังคับแต่ได้ 60 ชม. 1 · ยังไม่เริ่ม 1."""
    tsu_good = "กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์/สิ่งแวดล้อม)"
    people = {
        "complete": _student(session, criteria, "6900000011", completion=ImportedCompletion.passed),
        "no_elective": _student(session, criteria, "6900000012", completion=ImportedCompletion.failed),
        "no_mandatory": _student(session, criteria, "6900000013", completion=ImportedCompletion.passed),
        "nothing": _student(session, criteria, "6900000014", faculty="คณะอื่น", completion=ImportedCompletion.failed),
    }
    _give(session, people["complete"], FULL)
    _give(session, people["no_elective"], {**FULL, ELECTIVE: 0})
    _give(session, people["no_mandatory"], {**FULL, ORIENTATION: 0, tsu_good: 14})
    create_gold_layer(session)
    return people


def _admin(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def test_dashboard_passes_only_complete_students(client, tokens, cohort):
    body = client.get("/dashboard/overview", headers=_admin(tokens)).json()
    assert body["total_students"] == 4
    assert body["passed_count"] == 1  # คนที่ได้ 60 ชม. แต่ขาดปฐมนิเทศไม่นับ
    assert body["required_hours_total"] == 60

    faculties = {r["faculty"]: r for r in client.get("/dashboard/by-faculty", headers=_admin(tokens)).json()}
    assert faculties["คณะทดสอบ"]["passed_count"] == 1
    assert faculties["คณะอื่น"]["passed_count"] == 0


def test_dashboard_at_risk_uses_hours_that_count(client, tokens, cohort):
    body = client.get("/dashboard/at-risk?threshold=100", headers=_admin(tokens)).json()
    by_code = {s["student_code"]: s for s in body}

    assert set(by_code) == {"6900000012", "6900000013", "6900000014"}
    assert [s["student_code"] for s in body][0] == "6900000014"  # 0% เสี่ยงที่สุด
    assert by_code["6900000013"]["earned_hours"] == 56
    assert by_code["6900000013"]["missing_hours"] == 4
    assert by_code["6900000012"]["percent"] == 95


def test_dashboard_by_category_is_per_learning_unit(client, tokens, cohort):
    body = client.get("/dashboard/by-category", headers=_admin(tokens)).json()
    required = {r["category_name"]: r["required_hours"] for r in body}

    # เป้าต่อคนของ 2567-regular แยกตามหน่วยการเรียนรู้ รวม 60
    assert required == {
        "พัฒนาทักษะชีวิต": 9,
        "TSU รับใช้สังคม": 10,
        "ศิลปวัฒนธรรมอาเซียน": 10,
        "พัฒนาคุณธรรมและวินัย": 4,
        "ใฝ่เรียนรู้ตลอดชีวิต": 27,
    }


def test_at_risk_email_list_matches_the_dashboard(client, tokens, session, cohort):
    dashboard = client.get("/dashboard/at-risk", headers=_admin(tokens)).json()
    emails = collect_at_risk_students(session, threshold=50)

    assert [s.student_code for s in emails] == [s["student_code"] for s in dashboard] == ["6900000014"]
    everyone = {s.student_code: s for s in collect_at_risk_students(session, threshold=100)}
    assert [g.name for g in everyone["6900000013"].gaps] == [ORIENTATION]
    assert everyone["6900000013"].earned_hours == 56


def test_check_script_compares_with_the_file_status(session, cohort):
    report = compare(session)

    assert report.checked == 4
    # ไฟล์บอกว่าผ่าน แต่ขาดรายการบังคับ → ไม่ตรงหนึ่งคน · คนอื่นตรงหมด
    assert [m.student_code for m in report.mismatches] == ["6900000013"]
    assert report.table[("2567-regular", "passed", "ผ่าน")] == 1
    assert report.table[("2567-regular", "failed", "ไม่ผ่าน")] == 2


def _login_as(client, session, student):
    session.add(
        User(
            username=student.student_id,
            hashed_password=hash_password("pw123456"),
            role=UserRole.student,
            student_id=student.id,
        )
    )
    session.commit()
    token = client.post(
        "/auth/login", data={"username": student.student_id, "password": "pw123456"}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_student_hours_summary_is_grouped_by_talent(client, session, cohort):
    headers = _login_as(client, session, cohort["no_elective"])
    body = client.get("/students/me/hours-summary", headers=headers).json()

    assert [(t["name"], t["required_hours"]) for t in body] == [
        ("TSU Glocal Talent", 30),
        ("TSU Communication Talent", 10),
        ("TSU Social Innovation/Entrepreneurship Talent", 20),
    ]
    glocal = body[0]
    assert not glocal["completed"] and glocal["earned_hours"] == 27
    missing = [s["name"] for s in glocal["subcategories"] if not s["completed"]]
    assert missing == [ELECTIVE]
    assert body[1]["completed"] and body[2]["completed"]
    assert len(body[2]["subcategories"]) == 2  # แนวคิด (บังคับ) + กลุ่ม Social


def test_chatbot_missing_names_the_requirement_and_suggests_activities(client, session, cohort):
    """ถาม "ขาดหมวดไหน" ต้องได้ชื่อรายการเกณฑ์ ตัวเลขที่ขาด และกิจกรรมที่ลงได้

    เป็น structured query ล้วน ๆ (ไม่แตะ LLM) จึงต้องผ่านแม้ LLM_BACKEND=stub
    """
    upcoming = now_th_naive() + timedelta(days=7)
    _activity(session, [_req(session, ELECTIVE)], 3, start_at=upcoming, name="บริหารเวลาเปิดรับ")
    create_gold_layer(session)

    answer = answer_missing(session, cohort["no_elective"].id)
    assert answer.intent == Intent.MISSING
    # ชื่อรายการเกณฑ์ที่ขาด ไม่ใช่แค่ชื่อหมวดกว้าง ๆ
    assert ELECTIVE in answer.answer
    # ตัวเลขครบสามตัว
    assert "ต้องการ" in answer.answer and "ได้แล้ว" in answer.answer and "ขาดอีก" in answer.answer
    # กิจกรรมที่เปิดรับซึ่งนับเข้ารายการนั้น
    assert "บริหารเวลาเปิดรับ" in answer.answer
    assert [r["name"] for r in answer.rows[0]["suggestions"]] == ["บริหารเวลาเปิดรับ"]


def test_chatbot_recommends_upcoming_activities_for_missing_items(client, session, cohort):
    upcoming = now_th_naive() + timedelta(days=7)
    wanted = _activity(session, [_req(session, ELECTIVE)], 3, start_at=upcoming, name="บริหารเวลาเปิดรับ")
    _activity(session, [_req(session, ORIENTATION)], 4, start_at=upcoming, name="ปฐมนิเทศรอบใหม่")
    create_gold_layer(session)

    answer = recommend_by_missing_categories(session, cohort["no_elective"].id)
    # เฉพาะรายการที่ยังขาด (ปฐมนิเทศครบแล้ว) และเฉพาะรอบที่ยังสมัครได้ (ไม่ใช่รอบที่จัดไปแล้ว)
    assert {r["name"] for r in answer.rows} == {wanted.name}
    assert ELECTIVE in answer.answer

    headers = _login_as(client, session, cohort["no_elective"])
    hours = client.post("/chatbot/ask", json={"question": "ฉันได้กี่ชั่วโมงแล้ว"}, headers=headers).json()
    assert "จากเกณฑ์ 60 ชม." in hours["answer"]
    assert "ครบตามเกณฑ์แล้ว" not in hours["answer"]
