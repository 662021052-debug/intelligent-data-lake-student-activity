"""ลบกิจกรรมที่มีผู้เข้าร่วมแล้ว = ซ่อน ไม่ใช่ลบ (Prompt C)

ครอบคลุมทั้งสามด้านที่ต้องไม่พัง: กิจกรรมยังอยู่, นิสิตไม่เห็น/สมัครใหม่ไม่ได้,
และชั่วโมงที่นับไปแล้วใน gold ยังเท่าเดิม
"""

from datetime import datetime, timedelta, timezone

from sqlmodel import select
from sqlalchemy import text

from app.auth import hash_password
from app.gold import create_gold_layer
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

TZ_TH = timezone(timedelta(hours=7))


def _today_th() -> datetime:
    now = datetime.now(TZ_TH)
    return datetime(now.year, now.month, now.day)


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _make_activity(session, name="กิจกรรมมีคนลงแล้ว", days_ahead=7, hidden=False):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        subcategory_id=1,
        is_required=False,
        max_participants=50,
        start_at=_today_th() + timedelta(days=days_ahead),
        location="ห้อง SC101",
        hours=3,
        created_by=_staff_id(session),
        approval_status=ApprovalStatus.approved,
        is_hidden=hidden,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _make_student_user(session, client, username="hide_student", student_code="8501001"):
    student = Student(
        student_id=student_code,
        full_name="นิสิตทดสอบซ่อนกิจกรรม",
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)

    session.add(
        User(
            username=username,
            hashed_password=hash_password("pw123456"),
            role=UserRole.student,
            student_id=student.id,
        )
    )
    session.commit()
    login = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return student, {"Authorization": f"Bearer {login.json()['access_token']}"}


def _join(session, student, activity, hours=3.0, status=EvidenceStatus.approved):
    participation = Participation(
        student_id=student.id,
        activity_id=activity.id,
        evidence_status=status,
        hours_earned=hours,
    )
    session.add(participation)
    session.commit()
    session.refresh(participation)
    return participation


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


# ---------- ลบ vs ซ่อน ----------


def test_delete_with_participants_hides_instead_of_deleting(client, session):
    activity = _make_activity(session)
    student, _ = _make_student_user(session, client)
    participation = _join(session, student, activity)

    assert client.delete(f"/activities/{activity.id}").status_code == 204

    session.expire_all()
    assert session.get(Activity, activity.id).is_hidden is True
    # การเข้าร่วมเดิมต้องไม่หายไปไหน
    assert session.get(Participation, participation.id) is not None


def test_delete_without_participants_really_deletes(client, session):
    activity = _make_activity(session, name="กิจกรรมไม่มีคนลง")

    assert client.delete(f"/activities/{activity.id}").status_code == 204
    assert session.get(Activity, activity.id) is None


# ---------- ฝั่งนิสิต ----------


def test_student_cannot_see_hidden_activity(client, session, tokens):
    activity = _make_activity(session, name="กิจกรรมที่ถูกซ่อน")
    visible = _make_activity(session, name="กิจกรรมปกติ")
    student, headers = _make_student_user(session, client)
    _join(session, student, activity)
    client.delete(f"/activities/{activity.id}")

    listing = client.get("/activities", headers=headers).json()
    assert [a["name"] for a in listing["items"]] == ["กิจกรรมปกติ"]
    assert listing["total"] == 1
    assert visible.id is not None

    # เปิดตรง ๆ ด้วย id ก็ต้องไม่ได้
    assert client.get(f"/activities/{activity.id}", headers=headers).status_code == 403


def test_staff_and_admin_still_see_hidden_activity_with_flag(client, session, tokens):
    activity = _make_activity(session, name="กิจกรรมที่ถูกซ่อน")
    student, _ = _make_student_user(session, client)
    _join(session, student, activity)
    client.delete(f"/activities/{activity.id}")

    for headers in ({}, _admin_headers(tokens)):
        listing = client.get("/activities", headers=headers).json()
        rows = {a["name"]: a for a in listing["items"]}
        assert "กิจกรรมที่ถูกซ่อน" in rows
        assert rows["กิจกรรมที่ถูกซ่อน"]["is_hidden"] is True


def test_student_cannot_register_for_hidden_activity(client, session):
    activity = _make_activity(session, name="กิจกรรมที่ถูกซ่อน")
    joiner, _ = _make_student_user(session, client, "hide_joiner", "8501002")
    _join(session, joiner, activity)
    client.delete(f"/activities/{activity.id}")

    _, headers = _make_student_user(session, client, "hide_newcomer", "8501003")
    response = client.post(
        "/participations/register", json={"activity_id": activity.id}, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "กิจกรรมนี้ยังไม่เปิดรับสมัคร"


# ---------- เลิกซ่อน ----------


def test_unhide_brings_the_activity_back_for_students(client, session, tokens):
    activity = _make_activity(session, name="กิจกรรมที่จะกู้คืน")
    student, headers = _make_student_user(session, client)
    _join(session, student, activity)
    client.delete(f"/activities/{activity.id}")
    assert client.get("/activities", headers=headers).json()["total"] == 0

    response = client.patch(f"/activities/{activity.id}/unhide")
    assert response.status_code == 200
    assert response.json()["is_hidden"] is False
    # สถานะอนุมัติเดิมต้องไม่ถูกแตะ ไม่งั้นกลับมาแล้วนิสิตก็ยังไม่เห็นอยู่ดี
    assert response.json()["approval_status"] == "approved"

    assert [a["name"] for a in client.get("/activities", headers=headers).json()["items"]] == [
        "กิจกรรมที่จะกู้คืน"
    ]


def test_student_cannot_unhide(client, session, tokens):
    activity = _make_activity(session, name="กิจกรรมที่ถูกซ่อน", hidden=True)
    _, headers = _make_student_user(session, client)

    assert client.patch(f"/activities/{activity.id}/unhide", headers=headers).status_code == 403


def test_second_staff_cannot_unhide_someone_elses_activity(client, session, tokens):
    activity = _make_activity(session, name="กิจกรรมของ staff คนแรก", hidden=True)
    session.add(
        User(
            username="staff2",
            hashed_password=hash_password("pw123456"),
            role=UserRole.staff,
        )
    )
    session.commit()
    login = client.post("/auth/login", data={"username": "staff2", "password": "pw123456"})
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    assert client.patch(f"/activities/{activity.id}/unhide", headers=headers).status_code == 403


def test_unhide_nonexistent_activity_returns_404(client):
    assert client.patch("/activities/9999/unhide").status_code == 404


# ---------- gold layer ----------


def _make_category(session):
    category = HourCategory(name="ใฝ่เรียนรู้ตลอดชีวิต", required_hours=10)
    session.add(category)
    session.commit()
    session.refresh(category)
    sub = HourSubcategory(category_id=category.id, name="กิจกรรม ICT 1", required_hours=5)
    session.add(sub)
    session.commit()
    session.refresh(sub)
    return category, sub


def test_hidden_activity_keeps_already_earned_hours(client, session):
    """ชั่วโมงที่นับไปแล้วต้องไม่ขยับ — นี่คือเหตุผลทั้งหมดที่เลือกซ่อนแทนลบ"""
    category, sub = _make_category(session)
    activity = _make_activity(session, name="กิจกรรมที่ถูกซ่อน")
    activity.subcategory_id = sub.id
    session.add(activity)
    session.commit()
    student, _ = _make_student_user(session, client)
    _join(session, student, activity, hours=3.0)
    create_gold_layer(session)

    def earned():
        return session.execute(
            text(
                "SELECT earned_hours FROM gold_student_hours "
                "WHERE student_key = :sid AND category_key = :cid"
            ),
            {"sid": student.id, "cid": category.id},
        ).scalar()

    assert earned() == 3.0

    assert client.delete(f"/activities/{activity.id}").status_code == 204
    session.expire_all()
    assert earned() == 3.0


def test_hidden_activity_drops_out_of_the_chatbot_catalog(client, session):
    """แชตบอตต้องไม่แนะนำกิจกรรมที่สมัครไม่ได้แล้ว"""
    activity = _make_activity(session, name="กิจกรรมที่ถูกซ่อน")
    student, _ = _make_student_user(session, client)
    _join(session, student, activity)
    create_gold_layer(session)

    def catalog_names():
        return [row[0] for row in session.execute(text("SELECT name FROM gold_activity_catalog"))]

    assert "กิจกรรมที่ถูกซ่อน" in catalog_names()

    assert client.delete(f"/activities/{activity.id}").status_code == 204
    session.expire_all()
    assert "กิจกรรมที่ถูกซ่อน" not in catalog_names()
