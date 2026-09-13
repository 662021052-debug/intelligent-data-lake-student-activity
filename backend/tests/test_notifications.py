"""อีเมลแจ้งเตือนอัตโนมัติ (ข้อ 6.4) — Prompt 1

ทุกเคสใช้ StubEmailSender ที่เก็บอีเมลไว้ในหน่วยความจำ จึงตรวจได้ทั้ง "ส่งถึงใคร"
และ "เขียนว่าอะไร" โดยไม่มีทางยิงอีเมลจริงออกไประหว่างรันเทสต์

โลกจำลอง: เกณฑ์รวม 10 ชั่วโมงหนึ่งหมวด — เอ ครบ / บี ได้ 4 ชม. / ซี ได้ 0 ชม.
(ชุดเดียวกับ test_dashboard.py เพื่อให้เทียบกับรายชื่อบนแดชบอร์ดได้)
"""

from datetime import datetime, time as dtime, timedelta

import pytest
from sqlmodel import select

from app.email import EmailMessage, EmailSender as EmailSenderProtocol, StubEmailSender, get_email_sender
from app.gold import create_gold_layer
from app.main import app
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
)
from app.notifications import (
    AtRiskStudent,
    CategoryGap,
    announcement_blocker,
    build_activity_message,
    build_activity_reminder_message,
    build_at_risk_message,
    collect_at_risk_students,
    collect_tomorrow_activities,
    partition_by_email,
    tomorrow_window,
)
from app.timeutil import format_thai_datetime, now_th_naive


# ต่างจาก None ที่แปลว่า "ตั้งใจให้ไม่มีอีเมล"
_UNSET = object()


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _student(
    session,
    code,
    name,
    faculty="วิศวกรรมศาสตร์",
    year=2,
    status=StudentStatus.active,
    email=_UNSET,
):
    """นิสิตหนึ่งคน — ``email=None`` คือ "ยังไม่ระบุอีเมล" (ต้องถูกข้ามตอนส่ง)

    ดีฟอลต์เป็นที่อยู่มหาวิทยาลัยเหมือนที่ผู้ดูแลกดปุ่มเติมให้ในฟอร์ม เคสส่วนใหญ่
    สนใจว่า "ส่งถึงใคร" ไม่ใช่ "ใครมีอีเมล" จึงไม่ต้องกรอกซ้ำทุกครั้ง
    """
    student = Student(
        student_id=code,
        full_name=name,
        faculty=faculty,
        major="สาขาทดสอบ",
        year_level=year,
        status=status,
        email=f"{code}@tsu.ac.th" if email is _UNSET else email,
    )
    session.add(student)
    session.commit()
    session.refresh(student)
    return student


def _activity(session, sub_id, owner, *, start_at=None, max_participants=100, name="กิจกรรมทดสอบ",
              approval_status=ApprovalStatus.approved, is_hidden=False, location="หอประชุม",
              hours=10):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=False,
        max_participants=max_participants,
        start_at=start_at or (now_th_naive() + timedelta(days=7)),
        location=location,
        hours=hours,
        is_hidden=is_hidden,
        subcategory_id=sub_id,
        created_by=owner,
        approval_status=approval_status,
        approved_by=owner if approval_status == ApprovalStatus.approved else None,
        approved_at=datetime.utcnow() if approval_status == ApprovalStatus.approved else None,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _join(session, student_id, activity_id, hours, status=EvidenceStatus.approved):
    session.add(
        Participation(
            student_id=student_id,
            activity_id=activity_id,
            evidence_status=status,
            hours_earned=hours,
        )
    )
    session.commit()


@pytest.fixture(name="world")
def world_fixture(session):
    """เกณฑ์รวม 10 ชั่วโมง + นิสิต 3 คนที่ชั่วโมงต่างกัน + กิจกรรมในอนาคตหนึ่งรายการ"""
    category = HourCategory(name="กิจกรรมเพื่อสังคม", required_hours=10)
    session.add(category)
    session.commit()
    session.refresh(category)
    sub = HourSubcategory(category_id=category.id, name="จิตอาสา", required_hours=10)
    session.add(sub)
    session.commit()
    session.refresh(sub)

    staff = _staff_id(session)
    past_activity = _activity(
        session, sub.id, staff, start_at=now_th_naive() - timedelta(days=30), name="กิจกรรมที่จบไปแล้ว"
    )
    upcoming = _activity(session, sub.id, staff, name="ค่ายอาสาพัฒนาชนบท")

    a = _student(session, "660001", "เอ ครบแล้ว")
    b = _student(session, "660002", "บี ยังขาด")
    c = _student(session, "660003", "ซี ยังไม่เริ่ม", faculty="วิทยาศาสตร์", year=1)

    _join(session, a.id, past_activity.id, 10)  # ครบเกณฑ์
    _join(session, b.id, past_activity.id, 4)   # 40% -> เสี่ยง
    # ซี ไม่มีชั่วโมงเลย -> 0% เสี่ยงที่สุด

    create_gold_layer(session)
    return {"category": category, "sub": sub, "upcoming": upcoming, "past": past_activity,
            "a": a, "b": b, "c": c}


@pytest.fixture(name="mailbox")
def mailbox_fixture():
    """สลับตัวส่งอีเมลเป็น stub ตลอดการทดสอบ (แบบเดียวกับ storage ใน conftest)"""
    sender = StubEmailSender()
    app.dependency_overrides[get_email_sender] = lambda: sender
    yield sender
    app.dependency_overrides.pop(get_email_sender, None)


# --------------------------- ที่อยู่อีเมล ---------------------------
def test_recipients_are_split_by_whether_they_have_an_email():
    people = [("660001", "a@tsu.ac.th"), ("660002", None), ("660003", "   ")]
    sendable, skipped = partition_by_email(
        people, email_of=lambda p: p[1], code_of=lambda p: p[0]
    )

    assert [p[0] for p in sendable] == ["660001"]
    # ช่องว่างล้วนก็คือ "ยังไม่ระบุ" ไม่ใช่ที่อยู่ที่ส่งได้
    assert skipped == ["660002", "660003"]


def test_at_risk_message_refuses_a_student_without_an_email():
    """กันพลาดถ้ามีคนเรียกโดยไม่กรองก่อน — ดีกว่าปล่อย to=None ไปถึงตัวส่ง"""
    nobody = AtRiskStudent(
        student_key=1,
        student_code="660009",
        full_name="ไม่มีอีเมล",
        faculty="วิศวกรรมศาสตร์",
        year_level=2,
        earned_hours=0,
        required_hours=10,
        gaps=(),
        email=None,
    )
    with pytest.raises(ValueError, match="ยังไม่ระบุอีเมล"):
        build_at_risk_message(nobody)


# --------------------------- เนื้อความ (pure) ---------------------------
def _sample_at_risk():
    return AtRiskStudent(
        student_key=1,
        student_code="662021052",
        full_name="สมชาย ใจดี",
        faculty="วิศวกรรมศาสตร์",
        year_level=4,
        earned_hours=18,
        required_hours=60,
        gaps=(CategoryGap("กิจกรรมเพื่อสังคม", 8, 30),),
        email="662021052@tsu.ac.th",
    )


def test_at_risk_message_has_name_missing_hours_and_link():
    message = build_at_risk_message(_sample_at_risk())

    assert message.to == "662021052@tsu.ac.th"
    assert "42" in message.subject  # ขาดอีก 60 - 18 = 42 ชั่วโมง
    assert "สมชาย ใจดี" in message.body
    assert "662021052" in message.body
    assert "42" in message.body
    assert "http" in message.body  # ลิงก์กลับเข้าระบบ
    # ชั่วโมงกลม ๆ ต้องไม่โผล่เป็น 18.0 / 60.0 ในอีเมลที่นิสิตอ่าน
    assert "18.0" not in message.body and "60.0" not in message.body


def test_at_risk_message_lists_incomplete_categories():
    message = build_at_risk_message(_sample_at_risk())
    assert "รายการที่ยังทำไม่ครบ" in message.body
    assert "กิจกรรมเพื่อสังคม" in message.body
    assert "22" in message.body  # ขาดในหมวดนี้ 30 - 8


def test_activity_message_has_details_and_link(session, world):
    message = build_activity_message(
        student_name="สมหญิง เรียนดี",
        student_email="660003@tsu.ac.th",
        activity=world["upcoming"],
        category_name="กิจกรรมเพื่อสังคม › จิตอาสา",
        available_seats=42,
    )

    assert message.to == "660003@tsu.ac.th"
    assert "ค่ายอาสาพัฒนาชนบท" in message.subject
    assert "สมหญิง เรียนดี" in message.body
    assert "หอประชุม" in message.body
    assert "จิตอาสา" in message.body
    assert "42" in message.body
    assert "http" in message.body


# --------------------------- เลือกผู้รับ ---------------------------
def test_collect_at_risk_reads_gold_and_sorts_worst_first(session, world):
    at_risk = collect_at_risk_students(session, threshold=50)

    assert [s.student_code for s in at_risk] == ["660003", "660002"]  # 0% ก่อน 40%
    assert at_risk[1].earned_hours == 4
    assert at_risk[1].missing_hours == 6
    assert at_risk[1].percent == 40


def test_collect_at_risk_respects_threshold(session, world):
    # เกณฑ์ 100% -> คนที่ยังไม่ครบทุกคนติดหมด (เอ ครบพอดี 100% จึงไม่ติด)
    codes = [s.student_code for s in collect_at_risk_students(session, threshold=100)]
    assert codes == ["660003", "660002"]

    # เกณฑ์ 10% -> เหลือเฉพาะคนที่ยังไม่มีชั่วโมงเลย
    codes = [s.student_code for s in collect_at_risk_students(session, threshold=10)]
    assert codes == ["660003"]


def test_collect_at_risk_filters_by_faculty_and_year(session, world):
    codes = [s.student_code for s in collect_at_risk_students(session, faculty="วิทยาศาสตร์")]
    assert codes == ["660003"]

    codes = [s.student_code for s in collect_at_risk_students(session, year_level=2)]
    assert codes == ["660002"]


def test_inactive_students_are_never_emailed(session, world):
    dropped = _student(session, "660009", "นิสิตพ้นสภาพ", status=StudentStatus.inactive)
    create_gold_layer(session)

    codes = [s.student_code for s in collect_at_risk_students(session)]
    assert dropped.student_id not in codes


# --------------------------- endpoint: กลุ่มเสี่ยง ---------------------------
def test_admin_can_send_at_risk_emails(client, tokens, world, mailbox):
    response = client.post("/notifications/at-risk", headers=_admin_headers(tokens))

    assert response.status_code == 200
    body = response.json()
    assert body["sent"] == 2
    assert body["failed"] == 0
    assert set(body["recipients"]) == {"660002@tsu.ac.th", "660003@tsu.ac.th"}
    # ต้องไม่มีอีเมลถึงคนที่ชั่วโมงครบแล้ว
    assert all("660001" not in m.to for m in mailbox.sent)
    assert len(mailbox.sent) == 2


def test_students_without_an_email_are_skipped_and_counted(
    client, tokens, session, world, mailbox
):
    """นิสิตกลุ่มเสี่ยงที่ยังไม่ระบุอีเมลต้องไม่ถูกนับเป็น "ส่งแล้ว" และต้องรายงานจำนวนกลับ"""
    _student(session, "660004", "ดี ยังไม่ระบุอีเมล", email=None)
    create_gold_layer(session)

    response = client.post("/notifications/at-risk", headers=_admin_headers(tokens))

    assert response.status_code == 200
    body = response.json()
    assert body["sent"] == 2  # บี กับ ซี เท่านั้น
    assert body["failed"] == 0
    assert body["skipped"] == 1
    assert body["skipped_students"] == ["660004"]
    # คนที่ถูกข้ามต้องไม่มีอีเมลออกไปในชื่อของเขา ไม่ว่ารูปแบบไหน
    assert all("660004" not in m.to for m in mailbox.sent)
    assert len(mailbox.sent) == 2


def test_skipping_is_zero_when_everyone_has_an_email(client, tokens, world, mailbox):
    body = client.post("/notifications/at-risk", headers=_admin_headers(tokens)).json()

    assert body["skipped"] == 0
    assert body["skipped_students"] == []


def test_at_risk_endpoint_passes_filters_through(client, tokens, world, mailbox):
    response = client.post(
        "/notifications/at-risk",
        params={"faculty": "วิทยาศาสตร์"},
        headers=_admin_headers(tokens),
    )

    assert response.status_code == 200
    assert response.json()["recipients"] == ["660003@tsu.ac.th"]


def test_at_risk_is_admin_only(client, tokens, world, mailbox):
    # client ตัวปกติล็อกอินเป็น staff อยู่แล้ว
    assert client.post("/notifications/at-risk").status_code == 403

    student_headers = {"Authorization": f"Bearer {tokens['student']}"}
    assert client.post("/notifications/at-risk", headers=student_headers).status_code == 403
    assert mailbox.sent == []


# --------------------------- endpoint: ประชาสัมพันธ์กิจกรรม ---------------------------
def test_activity_announcement_goes_to_students_who_have_not_registered(
    client, tokens, session, world, mailbox
):
    _join(session, world["a"].id, world["upcoming"].id, 0, status=EvidenceStatus.pending)

    response = client.post(
        f"/notifications/activity/{world['upcoming'].id}", headers=_admin_headers(tokens)
    )

    assert response.status_code == 200
    recipients = set(response.json()["recipients"])
    assert recipients == {"660002@tsu.ac.th", "660003@tsu.ac.th"}  # เอ สมัครแล้ว ไม่ต้องชวนซ้ำ
    assert "ค่ายอาสาพัฒนาชนบท" in mailbox.sent[0].subject


def test_activity_announcement_skips_students_without_an_email(
    client, tokens, session, world, mailbox
):
    _student(session, "660005", "อี ยังไม่ระบุอีเมล", email=None)

    response = client.post(
        f"/notifications/activity/{world['upcoming'].id}", headers=_admin_headers(tokens)
    )

    assert response.status_code == 200
    body = response.json()
    assert body["skipped"] == 1
    assert body["skipped_students"] == ["660005"]
    assert set(body["recipients"]) == {
        "660001@tsu.ac.th",
        "660002@tsu.ac.th",
        "660003@tsu.ac.th",
    }


def test_activity_announcement_rejects_past_activity(client, tokens, world, mailbox):
    response = client.post(
        f"/notifications/activity/{world['past'].id}", headers=_admin_headers(tokens)
    )

    assert response.status_code == 400
    assert "เลยวันเวลา" in response.json()["detail"]
    assert mailbox.sent == []


def test_activity_announcement_rejects_unapproved_activity(
    client, tokens, session, world, mailbox
):
    pending = _activity(
        session,
        world["sub"].id,
        _staff_id(session),
        name="กิจกรรมรออนุมัติ",
        approval_status=ApprovalStatus.pending,
    )

    response = client.post(f"/notifications/activity/{pending.id}", headers=_admin_headers(tokens))

    assert response.status_code == 400
    assert "ยังไม่ได้รับอนุมัติ" in response.json()["detail"]
    assert mailbox.sent == []


def test_activity_announcement_rejects_full_activity(client, tokens, session, world, mailbox):
    full = _activity(session, world["sub"].id, _staff_id(session), max_participants=1, name="เต็มแล้ว")
    _join(session, world["a"].id, full.id, 0, status=EvidenceStatus.pending)

    response = client.post(f"/notifications/activity/{full.id}", headers=_admin_headers(tokens))

    assert response.status_code == 400
    assert "เต็ม" in response.json()["detail"]
    assert mailbox.sent == []


def test_activity_announcement_404_for_missing_activity(client, tokens, world, mailbox):
    assert client.post("/notifications/activity/99999", headers=_admin_headers(tokens)).status_code == 404


def test_activity_announcement_is_admin_only(client, tokens, world, mailbox):
    assert client.post(f"/notifications/activity/{world['upcoming'].id}").status_code == 403
    assert mailbox.sent == []


# --------------------------- เตือนกิจกรรมพรุ่งนี้ ---------------------------
@pytest.fixture(name="tomorrow")
def tomorrow_fixture(session, world):
    """กิจกรรมพรุ่งนี้หนึ่งรายการ + เอา/บี สมัครไว้ (ซี ไม่ได้สมัคร)

    ``start_at`` ตั้งเป็นเที่ยงวันพรุ่งนี้ตามเวลาไทย เพื่อไม่ให้เทสต์ไปคาบเกี่ยว
    เที่ยงคืนตอนรันจริงในช่วงหัวค่ำ
    """
    day = now_th_naive().date() + timedelta(days=1)
    activity = _activity(
        session,
        world["sub"].id,
        _staff_id(session),
        start_at=datetime.combine(day, dtime(12, 0)),
        name="อบรมปฐมพยาบาลเบื้องต้น",
        location="ห้องประชุม ชั้น 3 อาคารเรียนรวม",
        hours=6,
    )
    _join(session, world["a"].id, activity.id, 0, status=EvidenceStatus.pending)
    _join(session, world["b"].id, activity.id, 0, status=EvidenceStatus.pending)
    return activity


def test_tomorrow_window_follows_thai_time(): 
    """หน้าต่างต้องเป็น "ทั้งวันพรุ่งนี้" แบบครึ่งเปิด ไม่ใช่ 24 ชม. นับจากตอนนี้"""
    start, end = tomorrow_window(datetime(2026, 9, 13, 23, 30))

    assert start == datetime(2026, 9, 14, 0, 0)
    assert end == datetime(2026, 9, 15, 0, 0)


def test_reminder_picks_tomorrow_only_not_today_or_the_day_after(session, world, tomorrow):
    day = now_th_naive().date()
    _activity(
        session, world["sub"].id, _staff_id(session),
        start_at=datetime.combine(day, dtime(12, 0)), name="กิจกรรมวันนี้",
    )
    _activity(
        session, world["sub"].id, _staff_id(session),
        start_at=datetime.combine(day + timedelta(days=2), dtime(12, 0)), name="กิจกรรมมะรืนนี้",
    )
    for other in session.exec(select(Activity)).all():
        if other.id != tomorrow.id and other.name in ("กิจกรรมวันนี้", "กิจกรรมมะรืนนี้"):
            _join(session, world["a"].id, other.id, 0, status=EvidenceStatus.pending)

    names = [a.name for a, _ in collect_tomorrow_activities(session)]

    assert names == ["อบรมปฐมพยาบาลเบื้องต้น"]


def test_reminder_skips_unapproved_and_hidden_activities(session, world):
    day = now_th_naive().date() + timedelta(days=1)
    pending = _activity(
        session, world["sub"].id, _staff_id(session),
        start_at=datetime.combine(day, dtime(9, 0)), name="พรุ่งนี้แต่ยังไม่อนุมัติ",
        approval_status=ApprovalStatus.pending,
    )
    hidden = _activity(
        session, world["sub"].id, _staff_id(session),
        start_at=datetime.combine(day, dtime(9, 0)), name="พรุ่งนี้แต่ถูกยกเลิก",
        is_hidden=True,
    )
    _join(session, world["a"].id, pending.id, 0, status=EvidenceStatus.pending)
    _join(session, world["a"].id, hidden.id, 0, status=EvidenceStatus.pending)

    assert collect_tomorrow_activities(session) == []


def test_reminder_goes_only_to_students_who_registered(session, world, tomorrow):
    pairs = collect_tomorrow_activities(session)

    assert len(pairs) == 1
    activity, students = pairs[0]
    assert activity.id == tomorrow.id
    # ซี ไม่ได้สมัคร จึงต้องไม่อยู่ในรายชื่อ
    assert [s.student_id for s in students] == ["660001", "660002"]


def test_reminder_message_has_time_place_and_hours(session, world, tomorrow):
    message = build_activity_reminder_message(
        student_name="สมชาย ใจดี",
        student_email="660001@tsu.ac.th",
        activity=tomorrow,
    )

    assert message.to == "660001@tsu.ac.th"
    assert "อบรมปฐมพยาบาลเบื้องต้น" in message.subject
    assert "พรุ่งนี้" in message.subject
    assert "สมชาย ใจดี" in message.body
    assert format_thai_datetime(tomorrow.start_at) in message.body   # วันเวลา (เวลาไทย)
    assert "ห้องประชุม ชั้น 3 อาคารเรียนรวม" in message.body         # สถานที่
    assert "6 ชั่วโมง" in message.body                                # ชั่วโมงที่จะได้
    assert "http" in message.body
    # ชั่วโมงกลม ๆ ต้องไม่โผล่เป็น 6.0 ในอีเมลที่นิสิตอ่าน
    assert "6.0" not in message.body


def test_admin_can_send_activity_reminders(client, tokens, world, tomorrow, mailbox):
    response = client.post("/notifications/activity-reminders", headers=_admin_headers(tokens))

    assert response.status_code == 200
    body = response.json()
    assert body["sent"] == 2
    assert body["skipped"] == 0
    assert set(body["recipients"]) == {"660001@tsu.ac.th", "660002@tsu.ac.th"}
    assert len(mailbox.sent) == 2
    assert all("อบรมปฐมพยาบาลเบื้องต้น" in m.subject for m in mailbox.sent)


def test_reminder_skips_registered_students_without_an_email(
    client, tokens, session, world, tomorrow, mailbox
):
    nobody = _student(session, "660006", "เอฟ ยังไม่ระบุอีเมล", email=None)
    _join(session, nobody.id, tomorrow.id, 0, status=EvidenceStatus.pending)

    body = client.post(
        "/notifications/activity-reminders", headers=_admin_headers(tokens)
    ).json()

    assert body["sent"] == 2
    assert body["skipped"] == 1
    assert body["skipped_students"] == ["660006"]
    assert all("660006" not in m.to for m in mailbox.sent)


def test_dry_run_reports_recipients_without_sending(client, tokens, world, tomorrow, mailbox):
    body = client.post(
        "/notifications/activity-reminders",
        params={"dry_run": "true"},
        headers=_admin_headers(tokens),
    ).json()

    assert body["dry_run"] is True
    assert body["sent"] == 0
    assert set(body["recipients"]) == {"660001@tsu.ac.th", "660002@tsu.ac.th"}
    # สำคัญที่สุด: ต้องไม่มีอีเมลออกไปจริงแม้แต่ฉบับเดียว
    assert mailbox.sent == []


def test_reminders_report_dry_run_false_when_actually_sending(
    client, tokens, world, tomorrow, mailbox
):
    body = client.post("/notifications/activity-reminders", headers=_admin_headers(tokens)).json()
    assert body["dry_run"] is False


def test_no_activity_tomorrow_sends_nothing(client, tokens, world, mailbox):
    body = client.post("/notifications/activity-reminders", headers=_admin_headers(tokens)).json()

    assert body["sent"] == 0
    assert body["skipped"] == 0
    assert mailbox.sent == []


def test_activity_reminders_are_admin_only(client, tokens, world, tomorrow, mailbox):
    assert client.post("/notifications/activity-reminders").status_code == 403

    student_headers = {"Authorization": f"Bearer {tokens['student']}"}
    assert (
        client.post("/notifications/activity-reminders", headers=student_headers).status_code
        == 403
    )
    assert mailbox.sent == []


# --------------------------- กติกาว่าส่งได้/ไม่ได้ (pure) ---------------------------
def test_announcement_blocker_allows_upcoming_activity_with_seats(session, world):
    assert announcement_blocker(world["upcoming"], participant_count=0) is None


def test_announcement_blocker_reports_each_reason(session, world):
    activity = world["upcoming"]
    assert "เต็ม" in announcement_blocker(activity, participant_count=activity.max_participants)
    assert "เลยวันเวลา" in announcement_blocker(world["past"], participant_count=0)


# --------------------------- ตัวส่งอีเมล ---------------------------
def test_stub_sender_records_instead_of_sending():
    sender = StubEmailSender()
    message = build_at_risk_message(_sample_at_risk())

    sender.send(message)

    assert sender.sent == [message]
    sender.clear()
    assert sender.sent == []


def test_smtp_backend_falls_back_to_stub_without_a_host(monkeypatch):
    """ตั้ง EMAIL_BACKEND=smtp แต่ลืมใส่ SMTP_HOST ต้องไม่ล้มตอนส่ง — ตกกลับไปที่ stub
    แบบเดียวกับที่ llm.py ทำเมื่อไม่มี API key"""
    from app import email as email_module

    monkeypatch.setattr(email_module.settings, "email_backend", "smtp")
    monkeypatch.setattr(email_module.settings, "smtp_host", "")

    assert isinstance(email_module._build_sender(), StubEmailSender)


def test_smtp_sender_sends_utf8_through_the_connection(monkeypatch):
    """ตัวส่งจริง: ยืนยันหัวข้อ/เนื้อความภาษาไทยและขั้นตอน STARTTLS+login
    โดยสวม SMTP ปลอมแทนเซิร์ฟเวอร์จริง"""
    from app import email as email_module

    captured: dict = {}

    class FakeSMTP:
        def __init__(self, host, port, timeout=None):
            captured["host"], captured["port"] = host, port

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def starttls(self):
            captured["tls"] = True

        def login(self, username, password):
            captured["login"] = (username, password)

        def send_message(self, mime):
            captured["mime"] = mime

    monkeypatch.setattr(email_module.smtplib, "SMTP", FakeSMTP)
    sender = email_module.SmtpEmailSender(
        host="smtp.tsu.ac.th", port=587, username="bot", password="secret",
        sender="no-reply@tsu.ac.th",
    )

    sender.send(EmailMessage(to="660001@tsu.ac.th", subject="แจ้งเตือนชั่วโมง", body="สวัสดีครับ"))

    mime = captured["mime"]
    assert (captured["host"], captured["port"]) == ("smtp.tsu.ac.th", 587)
    assert captured["tls"] is True
    assert captured["login"] == ("bot", "secret")
    assert mime["To"] == "660001@tsu.ac.th"
    assert mime["From"] == "no-reply@tsu.ac.th"
    assert "แจ้งเตือนชั่วโมง" in str(mime["Subject"])
    assert "สวัสดีครับ" in mime.get_content()


def test_scheduler_stays_off_by_default(monkeypatch):
    """ค่าเริ่มต้นต้องไม่มี thread ตั้งเวลาโผล่มาเอง (และไม่ต้องมี apscheduler ติดตั้ง)"""
    from app import scheduler as scheduler_module

    monkeypatch.setattr(scheduler_module.settings, "notify_scheduler_enabled", False)
    assert scheduler_module.start_notification_scheduler() is None


def test_daily_job_swallows_errors(monkeypatch, caplog):
    """งานรายวันที่โยน exception จะถูก APScheduler ปิดทิ้งเงียบ ๆ จึงต้องกลืนเอง + log"""
    from app import scheduler as scheduler_module

    def _boom(*args, **kwargs):
        raise RuntimeError("ฐานข้อมูลล่ม")

    monkeypatch.setattr(scheduler_module, "send_at_risk_notifications", _boom)

    scheduler_module.run_at_risk_job()  # ต้องไม่โยนออกมา

    assert any("ล้มเหลว" in record.message for record in caplog.records)


def test_activity_reminder_job_swallows_errors(monkeypatch, caplog):
    """งานเตือนกิจกรรมก็ต้องกลืน exception เหมือนงานกลุ่มเสี่ยง ไม่งั้น APScheduler ปิดทิ้งเงียบ ๆ"""
    from app import scheduler as scheduler_module

    def _boom(*args, **kwargs):
        raise RuntimeError("ฐานข้อมูลล่ม")

    monkeypatch.setattr(scheduler_module, "send_activity_reminders", _boom)

    scheduler_module.run_activity_reminder_job()  # ต้องไม่โยนออกมา

    assert any("ล้มเหลว" in record.message for record in caplog.records)


def test_activity_reminder_job_uses_the_shared_sender(monkeypatch, session, world, tomorrow):
    """รอบอัตโนมัติต้องเดินทางเดียวกับ endpoint — ไม่ใช่โค้ดส่งคนละชุด"""
    from app import scheduler as scheduler_module

    calls = []

    def _spy(session_arg, sender_arg, **kwargs):
        calls.append(sender_arg)
        from app.notifications import NotificationReport

        return NotificationReport(subject="ทดสอบ")

    monkeypatch.setattr(scheduler_module, "send_activity_reminders", _spy)
    scheduler_module.run_activity_reminder_job()

    assert len(calls) == 1
    assert isinstance(calls[0], EmailSenderProtocol)


def test_one_failing_recipient_does_not_stop_the_rest(client, tokens, world):
    class FlakySender(StubEmailSender):
        def send(self, message):
            if message.to == "660002@tsu.ac.th":
                raise RuntimeError("mailbox full")
            super().send(message)

    sender = FlakySender()
    app.dependency_overrides[get_email_sender] = lambda: sender
    try:
        body = client.post("/notifications/at-risk", headers=_admin_headers(tokens)).json()
    finally:
        app.dependency_overrides.pop(get_email_sender, None)

    assert body["sent"] == 1
    assert body["failed"] == 1
    assert body["failed_recipients"] == ["660002@tsu.ac.th"]
    assert body["recipients"] == ["660003@tsu.ac.th"]
