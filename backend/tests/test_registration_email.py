"""อีเมลยืนยันการสมัคร (Email Notifications เฟส 1) + กันเตือนซ้ำด้วย participation.reminder_sent_at

กติกากันซ้ำ: กิจกรรมจัดภายใน "วันพรุ่งนี้" ตามเวลาไทย (ฐานเดียวกับตัวเตือน) → อีเมลยืนยันนับเป็นการเตือนแล้ว
ไม่มีอีเมลออกจริงระหว่างรันเทสต์ — ใช้ตัวหลอกสองแบบ:
* ``RecordingSmtp``  แทน SMTP ที่ *ใช้ได้* (ส่งสำเร็จ → ตั้ง reminder_sent_at)
* ``StubEmailSender`` แทนระบบที่ยังไม่ตั้งค่า SMTP (ไม่มีอะไรถึงผู้รับ → ไม่ตั้ง reminder_sent_at)

เฟส B: ทุกทางออกต้องมี log บอกเหตุผล และ reminder_sent_at ตั้งหลังส่งสำเร็จจริงเท่านั้น
"""

import logging
from datetime import datetime, time, timedelta

import pytest
from sqlmodel import select

from app import scheduler as scheduler_module
from app.auth import hash_password
from app.email import StubEmailSender, get_email_sender
from app.main import app
from app.models import Activity, ApprovalStatus, Participation, Student, StudentStatus, User, UserRole
from app.notifications import (
    RegistrationConfirmation,
    build_registration_confirmation_message,
    registration_counts_as_reminder,
    send_activity_reminders,
)
from app.timeutil import format_thai_datetime, now_th_naive


class RecordingSmtp:
    """ตัวหลอกของ SMTP ที่ทำงานปกติ — เก็บทุกฉบับไว้ใน ``sent``

    ต้องไม่ใช่ subclass ของ StubEmailSender: ตัวส่งจริงต้องแยกออกจาก stub ได้ ไม่งั้นเทสจะพิสูจน์
    ไม่ได้ว่า "ส่งสำเร็จจริงถึงตั้ง reminder_sent_at"
    """

    def __init__(self):
        self.sent = []

    def send(self, message):
        self.sent.append(message)


@pytest.fixture(name="mailbox")
def mailbox_fixture():
    sender = RecordingSmtp()
    app.dependency_overrides[get_email_sender] = lambda: sender
    yield sender
    app.dependency_overrides.pop(get_email_sender, None)


@pytest.fixture(name="unconfigured_mail")
def unconfigured_mail_fixture():
    """ระบบที่ยังไม่ตั้งค่า SMTP → ตกเป็น StubEmailSender"""
    sender = StubEmailSender()
    app.dependency_overrides[get_email_sender] = lambda: sender
    yield sender
    app.dependency_overrides.pop(get_email_sender, None)


class BrokenSmtp:
    def __init__(self, error=None):
        self._error = error or ConnectionRefusedError("SMTP ล่ม")

    def send(self, message):
        raise self._error


def _messages(caplog, level):
    return [r.getMessage() for r in caplog.records if r.levelno == level]


def _admin_id(session):
    return session.exec(select(User).where(User.username == "admin")).first().id


_CODE_EMAIL = object()


def _student_login(session, client, *, code="9102001", email=_CODE_EMAIL):
    """นิสิตที่ผูกบัญชีแล้ว — อีเมลดีฟอลต์ตามรหัส (``<code>@tsu.ac.th``) · ``email=None`` = ไม่มีอีเมล"""
    if email is _CODE_EMAIL:
        email = f"{code}@tsu.ac.th"
    student = Student(
        student_id=code,
        full_name="นางสาวทดสอบ อีเมลสมัคร",
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
        email=email,
    )
    session.add(student)
    session.commit()
    session.refresh(student)
    user = User(
        username=f"u{code}",
        hashed_password=hash_password("pw123456"),
        role=UserRole.student,
        student_id=student.id,
    )
    session.add(user)
    session.commit()
    token = client.post("/auth/login", data={"username": user.username, "password": "pw123456"}).json()[
        "access_token"
    ]
    return student, {"Authorization": f"Bearer {token}"}


def _day(offset: int, hour: int = 12) -> datetime:
    """เวลาไทยแบบไม่มีโซนของวันที่ ``วันนี้ + offset`` — ใช้วันตามปฏิทินให้ผลไม่ขึ้นกับเวลาที่รันเทสต์

    ``_day(1)`` = เที่ยงวันพรุ่งนี้ ซึ่งยังไม่เริ่มเสมอ (สมัครได้) ไม่ว่าจะรันตอนกี่โมง
    """
    return datetime.combine(now_th_naive().date() + timedelta(days=offset), time(hour, 0))


def _activity(session, *, start_at, name="ค่ายอาสาพัฒนาชนบท", location="หอประชุมใหญ่", hours=6.0):
    admin = _admin_id(session)
    activity = Activity(
        name=name,
        activity_type="จิตอาสา",
        is_required=False,
        max_participants=50,
        start_at=start_at,  # เวลาไทยแบบไม่มีโซน
        location=location,
        hours=hours,
        created_by=admin,
        approval_status=ApprovalStatus.approved,
        approved_by=admin,
        approved_at=datetime.utcnow(),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _register(client, headers, activity):
    response = client.post("/participations/register", json={"activity_id": activity.id}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def _participation(session, student, activity):
    return session.exec(
        select(Participation).where(
            Participation.student_id == student.id, Participation.activity_id == activity.id
        )
    ).one()


def _remind_day_before(session, activity):
    """รันตัวเตือนเสมือนเป็นวันก่อนกิจกรรม — "พรุ่งนี้" ของรอบนั้นคือวันจัดกิจกรรมพอดี"""
    reminders = StubEmailSender()
    report = send_activity_reminders(session, reminders, now=activity.start_at - timedelta(days=1))
    return reminders, report


# --------------------------- อีเมลตอนสมัคร ---------------------------
def test_register_sends_confirmation_with_activity_details(client, session, mailbox):
    activity = _activity(session, start_at=_day(7), hours=4.5)
    student, headers = _student_login(session, client)

    _register(client, headers, activity)

    assert len(mailbox.sent) == 1
    message = mailbox.sent[0]
    assert message.to == "9102001@tsu.ac.th"
    assert message.subject == f"[ยืนยันการสมัคร] {activity.name}"
    assert "นางสาวทดสอบ อีเมลสมัคร" in message.body
    assert format_thai_datetime(activity.start_at) in message.body, "วันเวลาต้องเป็นเวลาไทย"
    assert "หอประชุมใหญ่" in message.body
    assert "4.5 ชั่วโมง" in message.body
    assert "ไม่ส่งอีเมลเตือนซ้ำ" not in message.body
    # จัดหลังวันพรุ่งนี้ → ยังต้องได้อีเมลเตือนก่อน 1 วัน
    assert _participation(session, student, activity).reminder_sent_at is None


def test_student_without_email_registers_without_any_email(client, session, mailbox):
    activity = _activity(session, start_at=_day(1))
    student, headers = _student_login(session, client, code="9102002", email=None)

    _register(client, headers, activity)

    assert mailbox.sent == []
    # ไม่มีฉบับไหนทำหน้าที่เตือน จึงไม่ตั้งเครื่องหมาย แม้กิจกรรมจัดพรุ่งนี้
    assert _participation(session, student, activity).reminder_sent_at is None


def test_blank_email_is_treated_as_no_email(client, session, mailbox):
    activity = _activity(session, start_at=_day(3))
    _, headers = _student_login(session, client, code="9102003", email="   ")

    _register(client, headers, activity)

    assert mailbox.sent == []


def test_email_failure_does_not_fail_registration(client, session, caplog):
    app.dependency_overrides[get_email_sender] = lambda: BrokenSmtp()
    try:
        activity = _activity(session, start_at=_day(3))
        student, headers = _student_login(session, client, code="9102004")
        with caplog.at_level(logging.INFO, logger="uvicorn.error"):
            body = _register(client, headers, activity)
    finally:
        app.dependency_overrides.pop(get_email_sender, None)

    # สมัครสำเร็จเหมือนเดิม (ส่งอีเมลล้มต้องไม่ทำให้การสมัครล้ม)
    assert body["student_id"] == student.id
    assert _participation(session, student, activity) is not None
    # ...แต่ต้องเห็นชัดใน log ระดับ ERROR พร้อมผู้รับ ชนิดความล้มเหลว และ stack
    errors = [r for r in caplog.records if r.levelno == logging.ERROR]
    assert len(errors) == 1
    assert errors[0].getMessage().startswith("registration email: FAILED")
    assert "9102004@tsu.ac.th" in errors[0].getMessage()
    assert "connection_refused" in errors[0].getMessage()
    assert errors[0].exc_info is not None, "ต้องมี stack trace ไม่ใช่แค่ข้อความ"


def test_registration_email_switch_off_sends_nothing_and_marks_nothing(client, session, mailbox, monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "notify_registration_email_enabled", False)
    activity = _activity(session, start_at=_day(1))
    student, headers = _student_login(session, client, code="9102009")

    _register(client, headers, activity)

    assert mailbox.sent == []
    # ไม่ได้ส่งอีเมลยืนยัน → ตัวเตือน 1 วันต้องยังเตือนคนนี้ได้
    assert _participation(session, student, activity).reminder_sent_at is None
    reminders, report = _remind_day_before(session, activity)
    assert [m.to for m in reminders.sent] == ["9102009@tsu.ac.th"]


# --------------------------- เฟส B: log ทุกทางออก + reminder ตั้งหลังส่งจริง ---------------------------
def test_sent_successfully_logs_info_and_marks_reminder(client, session, mailbox, caplog):
    activity = _activity(session, start_at=_day(1))
    student, headers = _student_login(session, client, code="9102101")

    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        _register(client, headers, activity)

    participation = _participation(session, student, activity)
    sent = [m for m in _messages(caplog, logging.INFO) if m.startswith("registration email: sent to")]
    assert len(sent) == 1
    assert "9102101@tsu.ac.th" in sent[0]
    assert f"activity {activity.id}" in sent[0] and f"participation {participation.id}" in sent[0]
    assert participation.reminder_sent_at is not None, "ส่งสำเร็จ + กิจกรรมพรุ่งนี้ → นับเป็นการเตือนแล้ว"
    assert not _messages(caplog, logging.ERROR)


def test_smtp_failure_does_not_mark_reminder_so_daily_reminder_retries(client, session, caplog):
    """ช่องโหว่เดิม: ตั้ง reminder_sent_at ตอนสมัครก่อนส่ง → SMTP ล้มแล้วนิสิตไม่ได้อีเมลเลยทั้งสองฉบับ"""
    activity = _activity(session, start_at=_day(1))  # จัดพรุ่งนี้ = กรณีที่เคยถูกตั้งเครื่องหมายล่วงหน้า
    student, headers = _student_login(session, client, code="9102102")

    app.dependency_overrides[get_email_sender] = lambda: BrokenSmtp(TimeoutError("หมดเวลา"))
    try:
        with caplog.at_level(logging.INFO, logger="uvicorn.error"):
            _register(client, headers, activity)
    finally:
        app.dependency_overrides.pop(get_email_sender, None)

    errors = _messages(caplog, logging.ERROR)
    assert len(errors) == 1 and errors[0].startswith("registration email: FAILED")
    assert "timeout" in errors[0]
    assert not [m for m in _messages(caplog, logging.INFO) if "registration email: sent" in m]
    # ส่งไม่ถึง → ต้องไม่ตั้ง
    assert _participation(session, student, activity).reminder_sent_at is None

    # ...ตัวเตือนรายวันจึงยังเตือนคนนี้ได้ (นี่คือเป้าหมายของการแก้)
    reminders, report = _remind_day_before(session, activity)
    assert [m.to for m in reminders.sent] == ["9102102@tsu.ac.th"]
    assert report.sent == 1


def test_confirmation_sent_once_then_reminder_stays_deduped(client, session, mailbox):
    """ส่งสำเร็จแล้วต้องไม่ส่งซ้ำเหมือนเดิม — การย้ายจุดตั้งเครื่องหมายต้องไม่ทำ dedup พัง"""
    activity = _activity(session, start_at=_day(1))
    student, headers = _student_login(session, client, code="9102103")

    _register(client, headers, activity)

    assert len(mailbox.sent) == 1
    reminders, report = _remind_day_before(session, activity)
    assert reminders.sent == [] and report.sent == 0


def test_activity_after_tomorrow_is_never_marked_by_registration(client, session, mailbox):
    activity = _activity(session, start_at=_day(4))
    student, headers = _student_login(session, client, code="9102104")

    _register(client, headers, activity)

    assert len(mailbox.sent) == 1
    assert _participation(session, student, activity).reminder_sent_at is None


def test_no_email_logs_warning_and_names_the_student(client, session, mailbox, caplog):
    activity = _activity(session, start_at=_day(3))
    student, headers = _student_login(session, client, code="9102105", email=None)

    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        _register(client, headers, activity)

    warnings = [r for r in caplog.records if r.levelno == logging.WARNING]
    assert len(warnings) == 1
    assert warnings[0].getMessage().startswith(
        f"registration email: skipped — student {student.id} has no email"
    )
    assert mailbox.sent == []


def test_switch_off_logs_warning_naming_the_switch(client, session, mailbox, monkeypatch, caplog):
    from app.config import settings

    monkeypatch.setattr(settings, "notify_registration_email_enabled", False)
    activity = _activity(session, start_at=_day(3))
    _, headers = _student_login(session, client, code="9102106")

    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        _register(client, headers, activity)

    warnings = _messages(caplog, logging.WARNING)
    assert len(warnings) == 1
    assert "skipped — NOTIFY_REGISTRATION_EMAIL_ENABLED=false" in warnings[0]
    assert mailbox.sent == []


def test_stub_backend_logs_warning_and_does_not_mark_reminder(client, session, unconfigured_mail, caplog):
    """EMAIL_BACKEND=stub (หรือ smtp ที่ SMTP_HOST ว่าง) — ไม่มีอะไรถึงผู้รับ ต้องไม่นับว่าเตือนแล้ว"""
    activity = _activity(session, start_at=_day(1))
    student, headers = _student_login(session, client, code="9102107")

    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        _register(client, headers, activity)

    warnings = _messages(caplog, logging.WARNING)
    assert any("skipped — EMAIL_BACKEND=stub (or SMTP_HOST empty)" in m for m in warnings)
    assert not [m for m in _messages(caplog, logging.INFO) if "registration email: sent" in m], (
        "stub ไม่ได้ส่งจริง ห้ามล็อกว่า sent"
    )
    assert _participation(session, student, activity).reminder_sent_at is None


def test_smtp_selected_but_host_empty_falls_back_to_stub_loudly(monkeypatch, caplog):
    """email.py: เดิมตกเป็น stub เงียบสนิท — ตอนนี้ต้องบอกว่า .env อาจไปไม่ถึงคอนเทนเนอร์"""
    from app import email as email_module
    from app.config import settings

    monkeypatch.setattr(settings, "email_backend", "smtp")
    monkeypatch.setattr(settings, "smtp_host", "")
    with caplog.at_level(logging.WARNING, logger="uvicorn.error"):
        sender = email_module._build_sender()

    assert isinstance(sender, StubEmailSender)
    assert any("EMAIL_BACKEND=smtp but SMTP_HOST is empty" in r.getMessage() for r in caplog.records)


def test_configured_smtp_builds_real_sender_without_warning(monkeypatch, caplog):
    from app import email as email_module
    from app.config import settings

    monkeypatch.setattr(settings, "email_backend", "smtp")
    monkeypatch.setattr(settings, "smtp_host", "smtp.example.test")
    with caplog.at_level(logging.WARNING, logger="uvicorn.error"):
        sender = email_module._build_sender()

    assert isinstance(sender, email_module.SmtpEmailSender)
    assert not caplog.records


def test_reminder_bookkeeping_failure_is_logged_as_error_not_raised(session, caplog):
    """อีเมลออกไปแล้วแต่บันทึกล้ม → ต้องเห็นว่าอาจเตือนซ้ำ แต่ห้ามโยน exception กลับไป"""
    from app.notifications import send_registration_confirmation

    def broken_factory():
        raise RuntimeError("ฐานข้อมูลล่ม")

    confirmation = RegistrationConfirmation(
        to="x@tsu.ac.th",
        student_name="ทดสอบ",
        activity_name="งานทดสอบ",
        start_at=datetime(2026, 9, 22, 12, 0),
        location="ห้อง 1",
        hours=2,
        counts_as_reminder=True,
    )
    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        ok = send_registration_confirmation(
            RecordingSmtp(), confirmation, participation_id=1, activity_id=1, session_factory=broken_factory
        )

    assert ok is True, "อีเมลถึงผู้รับแล้ว ผลของการส่งต้องเป็นสำเร็จ"
    errors = _messages(caplog, logging.ERROR)
    assert len(errors) == 1 and "could not record reminder_sent_at" in errors[0]


# --------------------------- กันเตือนซ้ำ ---------------------------
def test_activity_tomorrow_gets_only_the_confirmation(client, session, mailbox):
    activity = _activity(session, start_at=_day(1))
    student, headers = _student_login(session, client, code="9102005")

    _register(client, headers, activity)

    assert len(mailbox.sent) == 1
    assert "ไม่ส่งอีเมลเตือนซ้ำ" in mailbox.sent[0].body
    assert _participation(session, student, activity).reminder_sent_at is not None

    reminders, report = _remind_day_before(session, activity)
    assert reminders.sent == [], "กิจกรรมจัดภายในวันพรุ่งนี้ ต้องได้อีเมลรอบเดียว"
    assert report.sent == 0 and report.skipped == 0


def test_activity_day_after_tomorrow_gets_confirmation_and_one_reminder(client, session, mailbox):
    activity = _activity(session, start_at=_day(2))
    student, headers = _student_login(session, client, code="9102006")

    _register(client, headers, activity)
    assert len(mailbox.sent) == 1
    assert _participation(session, student, activity).reminder_sent_at is None

    reminders, report = _remind_day_before(session, activity)
    assert [m.to for m in reminders.sent] == ["9102006@tsu.ac.th"]
    assert reminders.sent[0].subject.startswith("[เตือนล่วงหน้า]")
    assert report.sent == 1
    assert _participation(session, student, activity).reminder_sent_at is not None

    # รอบถัดไป (หรือผู้ดูแลกดส่งซ้ำ) ต้องไม่เตือนคนเดิมอีก
    again, again_report = _remind_day_before(session, activity)
    assert again.sent == [] and again_report.sent == 0


def test_failed_reminder_is_not_marked_so_it_can_retry(client, session, mailbox):
    activity = _activity(session, start_at=_day(2))
    student, headers = _student_login(session, client, code="9102007")
    _register(client, headers, activity)

    class BrokenSmtp:
        def send(self, message):
            raise TimeoutError("หมดเวลา")

    report = send_activity_reminders(session, BrokenSmtp(), now=activity.start_at - timedelta(days=1))
    assert report.failed == 1
    assert _participation(session, student, activity).reminder_sent_at is None, "ส่งไม่ถึงต้องไม่นับว่าเตือนแล้ว"


def test_dry_run_does_not_mark_anyone(client, session, mailbox):
    activity = _activity(session, start_at=_day(2))
    student, headers = _student_login(session, client, code="9102008")
    _register(client, headers, activity)

    report = send_activity_reminders(
        session, StubEmailSender(), now=activity.start_at - timedelta(days=1), dry_run=True
    )
    assert report.dry_run and report.recipients == ["9102008@tsu.ac.th"]
    assert _participation(session, student, activity).reminder_sent_at is None


# --------------------------- pure functions ---------------------------
def test_counts_as_reminder_uses_thai_calendar_tomorrow():
    registered = datetime(2026, 9, 15, 10, 0)  # 15 ก.ย. 10:00 น. เวลาไทย
    assert registration_counts_as_reminder(datetime(2026, 9, 15, 18, 0), registered) is True  # วันนี้
    # 29 ชม. แต่ยังเป็น "พรุ่งนี้" — กรณีที่กติกา ≤24 ชม. เดิมพลาด (ได้อีเมลยืนยัน + เตือนตอน 18:00 น.)
    assert registration_counts_as_reminder(datetime(2026, 9, 16, 15, 0), registered) is True
    assert registration_counts_as_reminder(datetime(2026, 9, 16, 23, 59), registered) is True
    assert registration_counts_as_reminder(datetime(2026, 9, 17, 0, 0), registered) is False  # มะรืน

    # สมัครดึก 23:59 น. กิจกรรมมะรืน 00:30 น. (ห่างแค่ 24.5 ชม.) — ตัวเตือนรอบเย็นพรุ่งนี้ยังเตือนได้
    assert registration_counts_as_reminder(datetime(2026, 9, 17, 0, 30), datetime(2026, 9, 15, 23, 59)) is False


def test_confirmation_message_is_plain_thai_text():
    message = build_registration_confirmation_message(
        RegistrationConfirmation(
            to="662021052@tsu.ac.th",
            student_name="นายทดสอบ ระบบ",
            activity_name="TSU English Camp ครั้งที่ 4/2569",
            start_at=datetime(2026, 9, 20, 8, 30),
            location="ศูนย์ประชุมนานาชาติ",
            hours=3,
        )
    )
    assert message.to == "662021052@tsu.ac.th"
    assert message.subject == "[ยืนยันการสมัคร] TSU English Camp ครั้งที่ 4/2569"
    assert format_thai_datetime(datetime(2026, 9, 20, 8, 30)) in message.body
    assert "3 ชั่วโมง" in message.body


# --------------------------- สวิตช์ scheduler ---------------------------
class _FakeScheduler:
    def __init__(self, timezone=None):
        self.timezone = timezone
        self.job_ids = []
        self.started = False

    def add_job(self, func, **kwargs):
        self.job_ids.append(kwargs["id"])

    def start(self):
        self.started = True

    def shutdown(self, wait=False):
        self.started = False


@pytest.mark.parametrize(
    ("at_risk", "reminder", "expected"),
    [
        (False, True, [scheduler_module.REMINDER_JOB_ID]),
        (True, False, [scheduler_module.AT_RISK_JOB_ID]),
        (True, True, [scheduler_module.AT_RISK_JOB_ID, scheduler_module.REMINDER_JOB_ID]),
    ],
)
def test_each_job_has_its_own_switch(monkeypatch, at_risk, reminder, expected):
    background = pytest.importorskip("apscheduler.schedulers.background")
    monkeypatch.setattr(background, "BackgroundScheduler", _FakeScheduler)
    monkeypatch.setattr(scheduler_module, "_scheduler", None)
    monkeypatch.setattr(scheduler_module.settings, "notify_scheduler_enabled", True)
    monkeypatch.setattr(scheduler_module.settings, "notify_at_risk_enabled", at_risk)
    monkeypatch.setattr(scheduler_module.settings, "notify_reminder_enabled", reminder)

    scheduler = scheduler_module.start_notification_scheduler()

    assert scheduler.job_ids == expected
    assert scheduler.timezone == "Asia/Bangkok"
    assert scheduler.started


def test_scheduler_not_started_when_every_job_is_off(monkeypatch):
    monkeypatch.setattr(scheduler_module, "_scheduler", None)
    monkeypatch.setattr(scheduler_module.settings, "notify_scheduler_enabled", True)
    monkeypatch.setattr(scheduler_module.settings, "notify_at_risk_enabled", False)
    monkeypatch.setattr(scheduler_module.settings, "notify_reminder_enabled", False)

    assert scheduler_module.start_notification_scheduler() is None


def test_defaults_keep_at_risk_emails_off():
    """เปิด scheduler เพื่อเตือนกิจกรรมต้องไม่พาอีเมลกลุ่มเสี่ยงออกไปด้วย · อีเมลยืนยันการสมัครเปิดไว้"""
    from app.config import Settings

    defaults = Settings.model_fields
    assert defaults["notify_scheduler_enabled"].default is False
    assert defaults["notify_reminder_enabled"].default is True
    assert defaults["notify_at_risk_enabled"].default is False
    assert defaults["notify_registration_email_enabled"].default is True
    assert "notify_registration_covers_reminder_hours" not in defaults
