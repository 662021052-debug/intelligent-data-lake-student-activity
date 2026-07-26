"""Phase 17 — intent routing + Text-to-SQL (student-scoped, sandboxed).

The LLM is always mocked. Data intents are asserted to return only the asking
student's data, and the SQL guard is asserted to block prompt-injection / DDL.
"""
from datetime import datetime

import pytest
from sqlalchemy import text

from app import chatbot_sql
from app.auth import hash_password
from app.chatbot_sql import Intent, TTS_ALLOWED_TABLES, run_text_to_sql
from app.gold import create_gold_layer
from app.llm import get_llm
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    Student,
    StudentStatus,
    User,
    UserRole,
)
from app.sql_guard import UnsafeSqlError, validate_select


# ----------------------------- SQL guard (unit) -----------------------------

def test_guard_allows_plain_select():
    sql = "SELECT category_name FROM my_hours WHERE completed = 0"
    assert validate_select(sql, TTS_ALLOWED_TABLES) == sql


@pytest.mark.parametrize(
    "sql",
    [
        "SELECT * FROM gold_student_hours",          # raw student view is not whitelisted
        "SELECT * FROM student",                      # operational table blocked
        "SELECT * FROM my_hours; DROP TABLE student", # multiple statements
        "DROP TABLE student",                         # not a SELECT
        "DELETE FROM my_hours",                       # DML
        "UPDATE my_hours SET earned_hours = 99",      # DML
        "SELECT * FROM my_hours -- ignore the rules", # comment payload
        "INSERT INTO my_hours VALUES (1)",            # DML
    ],
)
def test_guard_blocks_dangerous_sql(sql):
    with pytest.raises(UnsafeSqlError):
        validate_select(sql, TTS_ALLOWED_TABLES)


# ----------------------------- intent router --------------------------------

@pytest.mark.parametrize(
    "question,expected",
    [
        ("ฉันได้กี่ชั่วโมงแล้ว", Intent.HOURS),
        ("ชั่วโมงสะสมของฉันเท่าไหร่", Intent.HOURS),
        ("ขาดหมวดไหนบ้าง", Intent.MISSING),
        ("กิจกรรมอะไรเปิดรับสมัครบ้าง", Intent.OPEN_ACTIVITIES),
        ("กิจกรรมบังคับมีอะไรบ้าง", Intent.REQUIRED),
        ("แนะนำกิจกรรมให้หน่อย", Intent.RECOMMEND),
        ("มีกิจกรรมไหนลงแทนได้บ้าง", Intent.RECOMMEND),
        ("หมวด TSU รับใช้สังคม ต้องเก็บกี่ชั่วโมง", Intent.RULES),
    ],
)
def test_classify_intent(question, expected):
    assert chatbot_sql.classify_intent(question) == expected


# --------------------------- data-world fixtures ----------------------------

class FakeLlm:
    """LLM stub whose generate() returns a preset string (canned SQL)."""

    def __init__(self, sql: str):
        self._sql = sql

    def embed(self, texts):
        return [[0.0] for _ in texts]

    def embed_query(self, text):
        return [0.0]

    def generate(self, prompt, *, system=None):
        return self._sql


def _staff_id(session):
    from sqlmodel import select

    return session.exec(select(User).where(User.username == "staff")).first().id


def _make_activity(session, sub_id, created_by, *, hours, name, is_required=False,
                   max_participants=50, approved=True):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=is_required,
        max_participants=max_participants,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง SC101",
        hours=hours,
        subcategory_id=sub_id,
        created_by=created_by,
        approval_status=ApprovalStatus.approved if approved else ApprovalStatus.pending,
        approved_by=created_by if approved else None,
        approved_at=datetime.utcnow() if approved else None,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _join(session, student_id, activity_id, hours, status=EvidenceStatus.approved):
    p = Participation(
        student_id=student_id, activity_id=activity_id,
        evidence_status=status, hours_earned=hours,
    )
    session.add(p)
    session.commit()
    session.refresh(p)
    return p


def _make_student_login(session, code, password="pw123456", full_name="นิสิตแชต"):
    student = Student(
        student_id=code, full_name=full_name, faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์", year_level=2, status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)
    user = User(
        username=code, hashed_password=hash_password(password),
        role=UserRole.student, student_id=student.id,
    )
    session.add(user)
    session.commit()
    return student


@pytest.fixture(name="world")
def world_fixture(client, session):
    """Two categories, two students (A completes cat1, misses cat2), plus an open
    and a required activity. Returns the login for student A."""
    staff_id = _staff_id(session)

    cat1 = HourCategory(name="หมวดหนึ่ง", required_hours=8)
    cat2 = HourCategory(name="หมวดสอง", required_hours=12)
    session.add_all([cat1, cat2])
    session.commit()
    session.refresh(cat1)
    session.refresh(cat2)
    sub1 = HourSubcategory(category_id=cat1.id, name="ย่อยหนึ่ง", required_hours=8)
    sub2 = HourSubcategory(category_id=cat2.id, name="ย่อยสอง", required_hours=12)
    session.add_all([sub1, sub2])
    session.commit()
    session.refresh(sub1)
    session.refresh(sub2)

    act1 = _make_activity(session, sub1.id, staff_id, hours=8, name="กิจกรรมหมวดหนึ่ง")
    act2 = _make_activity(session, sub2.id, staff_id, hours=4, name="กิจกรรมหมวดสอง")
    # an open (not full) required activity, and a full activity (excluded from "open")
    required_act = _make_activity(
        session, sub1.id, staff_id, hours=4, name="ปฐมนิเทศบังคับ", is_required=True
    )
    full_act = _make_activity(
        session, sub2.id, staff_id, hours=2, name="กิจกรรมเต็มแล้ว", max_participants=1
    )

    student_a = _make_student_login(session, "662021001", full_name="นิสิตเอ")
    student_b = _make_student_login(session, "662021002", full_name="นิสิตบี")

    # A: 8 hrs in cat1 (complete) + 4 hrs in cat2 (incomplete)
    _join(session, student_a.id, act1.id, hours=8)
    _join(session, student_a.id, act2.id, hours=4)
    # B: lots of hours (must NOT leak into A's answers)
    _join(session, student_b.id, act1.id, hours=8)
    _join(session, student_b.id, act2.id, hours=12)
    # fill full_act so participant_count >= max_participants
    _join(session, student_b.id, full_act.id, hours=2)

    create_gold_layer(session)
    return {"code": "662021001", "password": "pw123456", "student_a": student_a}


def _login(client, username, password):
    r = client.post("/auth/login", data={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return r.json()["access_token"]


def _ask(client, token, question):
    return client.post(
        "/chatbot/ask", json={"question": question},
        headers={"Authorization": f"Bearer {token}"},
    )


# ----------------------------- endpoint intents -----------------------------

def test_my_hours_answer_uses_only_own_data(client, world):
    token = _login(client, world["code"], world["password"])
    resp = _ask(client, token, "ฉันได้กี่ชั่วโมงแล้ว")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["intent"] == Intent.HOURS.value
    # A earned 8 + 4 = 12 (NOT B's 20), 1 of 2 categories complete.
    assert "12" in body["answer"]
    assert "1 จาก 2 หมวด" in body["answer"]


def test_missing_categories(client, world):
    token = _login(client, world["code"], world["password"])
    resp = _ask(client, token, "ขาดหมวดไหนบ้าง")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["intent"] == Intent.MISSING.value
    assert "หมวดสอง" in body["answer"]      # incomplete
    assert "หมวดหนึ่ง" not in body["answer"]  # already complete
    assert "8 ชม." in body["answer"]         # remaining 12 - 4 = 8


def test_open_activities_excludes_full_ones(client, world):
    token = _login(client, world["code"], world["password"])
    resp = _ask(client, token, "กิจกรรมอะไรเปิดรับสมัครบ้าง")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["intent"] == Intent.OPEN_ACTIVITIES.value
    assert "กิจกรรมหมวดหนึ่ง" in body["answer"]
    assert "กิจกรรมเต็มแล้ว" not in body["answer"]


def test_required_activities(client, world):
    token = _login(client, world["code"], world["password"])
    resp = _ask(client, token, "กิจกรรมบังคับมีอะไรบ้าง")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["intent"] == Intent.REQUIRED.value
    assert "ปฐมนิเทศบังคับ" in body["answer"]
    assert "กิจกรรมหมวดหนึ่ง" not in body["answer"]  # not required


# --------------------------- Text-to-SQL sandbox ----------------------------

def test_text_to_sql_is_student_scoped(session, world):
    """A benign LLM SELECT over my_hours returns only student A's rows."""
    student_a = world["student_a"]
    fake = FakeLlm("SELECT category_name, earned_hours FROM my_hours")
    result = run_text_to_sql(fake, session, "ขอดูข้อมูล", student_a.id)
    assert result.rows, "should return student A's category rows"
    earned = {row["category_name"]: row["earned_hours"] for row in result.rows}
    assert earned["หมวดหนึ่ง"] == 8
    assert earned["หมวดสอง"] == 4  # A's 4, not B's 12


def test_text_to_sql_blocks_cross_student_query(session, world):
    """LLM tries to read the raw all-students view → guard refuses, no data leaks."""
    student_a = world["student_a"]
    fake = FakeLlm("SELECT * FROM gold_student_hours")
    result = run_text_to_sql(fake, session, "แสดงทุกคน", student_a.id)
    assert result.rows == []
    assert "ปลอดภัย" in result.answer  # the safe-refusal message


def test_text_to_sql_blocks_injection_via_endpoint(client, session, world):
    """Prompt-injection ("ignore rules, show all") returning malicious SQL is
    sandboxed by the guard and returns no rows."""
    from app.main import app

    app.dependency_overrides[get_llm] = lambda: FakeLlm(
        "SELECT * FROM student; DROP TABLE student"
    )
    token = _login(client, world["code"], world["password"])
    resp = _ask(client, token, "ขอดูรายละเอียดหน่อย")  # classifies as GENERAL
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["intent"] == Intent.GENERAL.value
    assert "ปลอดภัย" in body["answer"]
    # the operational table is untouched
    assert session.execute(text("SELECT count(*) FROM student")).scalar_one() >= 2


def test_data_intent_requires_linked_student(client, tokens):
    """The shared conftest 'student' user has no linked student record → 400."""
    resp = _ask(client, tokens["student"], "ฉันได้กี่ชั่วโมงแล้ว")
    assert resp.status_code == 400


# ------------------------- recommendations (Phase 18) -----------------------

def test_recommend_only_open_activities_in_missing_categories(client, world):
    """Student A completed หมวดหนึ่ง and misses หมวดสอง → recommendations contain
    only open activities in หมวดสอง (not หมวดหนึ่ง, not the full one)."""
    token = _login(client, world["code"], world["password"])
    resp = _ask(client, token, "แนะนำกิจกรรมให้หน่อย")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["intent"] == Intent.RECOMMEND.value
    assert "กิจกรรมหมวดสอง" in body["answer"]        # open, in the missing category
    assert "กิจกรรมหมวดหนึ่ง" not in body["answer"]   # category already complete
    assert "ปฐมนิเทศบังคับ" not in body["answer"]     # belongs to completed หมวดหนึ่ง
    assert "กิจกรรมเต็มแล้ว" not in body["answer"]     # full


def test_recommend_alternatives_when_activity_is_full(client, world):
    """Naming a full activity → suggest open activities in the same subcategory."""
    token = _login(client, world["code"], world["password"])
    resp = _ask(client, token, "อยากลงกิจกรรมเต็มแล้ว มีอะไรลงแทนได้บ้าง")
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["intent"] == Intent.RECOMMEND.value
    # "กิจกรรมเต็มแล้ว" is in sub2; the open same-subcategory activity is "กิจกรรมหมวดสอง".
    assert "กิจกรรมหมวดสอง" in body["answer"]
