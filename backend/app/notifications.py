"""แจ้งเตือนทางอีเมล (ข้อ 6.4) — เลือกผู้รับ + เขียนเนื้อความ

สองแบบตามที่กำหนดไว้:

1. **นิสิตกลุ่มเสี่ยง** — ชั่วโมงสะสมยังไม่ถึงเกณฑ์ อ่านจาก ``gold_student_hours``
   (Gold Layer) เหมือนที่แดชบอร์ดใช้ รายชื่อที่ได้รับอีเมลจึงตรงกับรายชื่อบน
   หน้าแดชบอร์ดเสมอ ไม่ใช่คนละชุดเพราะคำนวณคนละที่
2. **ประชาสัมพันธ์กิจกรรม** — กิจกรรมที่อนุมัติแล้ว ยังไม่ถึงวันจัด และยังไม่เต็ม
   ส่งถึงนิสิตที่ยังไม่ได้สมัครกิจกรรมนั้น

ฟังก์ชันเลือกผู้รับกับฟังก์ชันเขียนเนื้อความแยกจากกัน และตัวเขียนเนื้อความเป็น
pure function ทั้งหมด — เทสต์ข้อความภาษาไทยได้โดยไม่ต้องมีฐานข้อมูล

**ที่อยู่อีเมลของนิสิตอนุมานจากรหัสนิสิต** (`<รหัส>@tsu.ac.th`) เพราะตาราง
``student`` ยังไม่มีคอลัมน์อีเมล — ถ้าจะเก็บอีเมลรายคนจริง ๆ ต้องเพิ่มคอลัมน์
พร้อม migration แล้วเปลี่ยนเฉพาะ :func:`student_email` จุดเดียว
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

from sqlalchemy import text
from sqlmodel import Session, select

from app.completion import progress_by_student
from app.config import settings
from app.email import EmailMessage, EmailSender
from app.models import (
    Activity,
    ActivityRequirement,
    ApprovalStatus,
    HourSubcategory,
    Participation,
    Requirement,
    Student,
)
from app.timeutil import format_thai_datetime, now_th_naive

logger = logging.getLogger(__name__)


# --------------------------- โครงข้อมูล ---------------------------
@dataclass(frozen=True)
class CategoryGap:
    """หมวดชั่วโมงหนึ่งหมวดที่นิสิตยังทำไม่ครบ"""

    name: str
    earned_hours: float
    required_hours: float

    @property
    def missing_hours(self) -> float:
        return max(self.required_hours - self.earned_hours, 0.0)


@dataclass(frozen=True)
class AtRiskStudent:
    student_key: int
    student_code: str
    full_name: str
    faculty: str
    year_level: int
    earned_hours: float
    required_hours: float
    gaps: tuple[CategoryGap, ...]

    @property
    def missing_hours(self) -> float:
        return max(self.required_hours - self.earned_hours, 0.0)

    @property
    def percent(self) -> float:
        return (self.earned_hours / self.required_hours * 100) if self.required_hours else 0.0


@dataclass
class NotificationReport:
    """ผลของการสั่งส่งหนึ่งครั้ง — ตอบกลับให้ผู้ดูแลเห็นว่าส่งถึงใครไปแล้วบ้าง"""

    subject: str
    sent: int = 0
    failed: int = 0
    recipients: list[str] = field(default_factory=list)
    failed_recipients: list[str] = field(default_factory=list)


# --------------------------- ตัวช่วยเล็ก ๆ ---------------------------
def format_hours(value: float) -> str:
    """4.0 → "4" แต่ 4.5 ยังเป็น "4.5" — เลขกลม ๆ ในอีเมลอ่านง่ายกว่า"""
    return str(int(value)) if float(value).is_integer() else str(value)


def student_email(student_code: str) -> str:
    """ที่อยู่อีเมลของนิสิตตามรูปแบบของมหาวิทยาลัย (เช่น 662021052@tsu.ac.th)"""
    return f"{student_code.strip()}@{settings.student_email_domain}"


def app_url() -> str:
    """ลิงก์หน้าเว็บนิสิตที่แนบไปในอีเมล — ใช้ค่าเดียวกับที่ QR เช็กอินใช้"""
    base = settings.public_app_base_url.strip().rstrip("/")
    if "://" not in base:
        base = f"https://{base}"
    return base


_SIGNATURE = (
    "\n---\n"
    "อีเมลฉบับนี้ส่งจากระบบติดตามการเข้าร่วมกิจกรรมนิสิตโดยอัตโนมัติ กรุณาอย่าตอบกลับ\n"
    "หากมีข้อสงสัย ติดต่อฝ่ายกิจการนิสิต"
)


# --------------------------- เนื้อความ (pure) ---------------------------
def build_at_risk_message(student: AtRiskStudent) -> EmailMessage:
    """อีเมลเตือนนิสิตที่ชั่วโมงยังไม่ครบเกณฑ์"""
    missing = format_hours(student.missing_hours)
    lines = [
        f"เรียน {student.full_name} (รหัสนิสิต {student.student_code})",
        "",
        "ระบบตรวจพบว่าชั่วโมงกิจกรรมของคุณยังไม่ครบตามเกณฑ์ที่มหาวิทยาลัยกำหนด",
        f"ขณะนี้คุณมีชั่วโมงที่นับเข้าเกณฑ์แล้ว {format_hours(student.earned_hours)} "
        f"จาก {format_hours(student.required_hours)} ชั่วโมง (คิดเป็น {student.percent:.0f}%)",
        f"ยังขาดอีก {missing} ชั่วโมง",
    ]

    if student.gaps:
        lines += ["", "รายการที่ยังทำไม่ครบ:"]
        lines += [
            f"  - {gap.name}: ได้ {format_hours(gap.earned_hours)} "
            f"จาก {format_hours(gap.required_hours)} ชั่วโมง "
            f"(ขาดอีก {format_hours(gap.missing_hours)} ชั่วโมง)"
            for gap in student.gaps
        ]

    lines += [
        "",
        "ดูชั่วโมงสะสมของคุณและสมัครกิจกรรมที่ยังเปิดรับได้ที่",
        f"  {app_url()}",
        "",
        "หากคุณเข้าร่วมกิจกรรมแล้วแต่ชั่วโมงยังไม่ขึ้น กรุณาอัปโหลดหลักฐานเพื่อรอเจ้าหน้าที่ตรวจสอบ",
        _SIGNATURE,
    ]

    return EmailMessage(
        to=student_email(student.student_code),
        subject=f"[แจ้งเตือน] ชั่วโมงกิจกรรมของคุณยังขาดอีก {missing} ชั่วโมง",
        body="\n".join(lines),
    )


def build_activity_message(
    *,
    student_name: str,
    student_code: str,
    activity: Activity,
    category_name: Optional[str],
    available_seats: int,
) -> EmailMessage:
    """อีเมลประชาสัมพันธ์กิจกรรมที่กำลังเปิดรับสมัคร"""
    lines = [
        f"เรียน {student_name}",
        "",
        f"ขอเชิญเข้าร่วมกิจกรรม “{activity.name}”",
        "",
        f"  ประเภท        : {activity.activity_type}",
    ]
    if category_name:
        lines.append(f"  หมวดชั่วโมง   : {category_name}")
    lines += [
        f"  วันเวลา       : {format_thai_datetime(activity.start_at)}",
        f"  สถานที่       : {activity.location}",
        f"  ชั่วโมงที่ได้รับ : {format_hours(activity.hours)} ชั่วโมง",
        f"  ที่นั่งคงเหลือ  : {available_seats} จาก {activity.max_participants} ที่นั่ง",
        "",
        "สมัครเข้าร่วมได้ที่",
        f"  {app_url()}",
        "",
        "ที่นั่งมีจำนวนจำกัด เมื่อเต็มแล้วระบบจะปิดรับสมัครทันที",
        _SIGNATURE,
    ]

    return EmailMessage(
        to=student_email(student_code),
        subject=f"[ประชาสัมพันธ์] ขอเชิญเข้าร่วมกิจกรรม {activity.name}",
        body="\n".join(lines),
    )


def announcement_blocker(activity: Activity, participant_count: int, now: Optional[datetime] = None) -> Optional[str]:
    """เหตุผลภาษาไทยที่ยัง "ประชาสัมพันธ์กิจกรรมนี้ไม่ได้" (None = ส่งได้)

    แยกเป็น pure function เพื่อให้เทสต์ครอบทุกเงื่อนไขได้โดยไม่ต้องยิง endpoint
    และเพื่อให้ router มีหน้าที่แค่แปลงเป็น HTTP 400
    """
    if activity.approval_status != ApprovalStatus.approved:
        return "กิจกรรมนี้ยังไม่ได้รับอนุมัติ จึงยังประชาสัมพันธ์ไม่ได้"
    if activity.start_at < (now or now_th_naive()):
        return "กิจกรรมนี้เลยวันเวลาที่จัดไปแล้ว"
    if participant_count >= activity.max_participants:
        return "กิจกรรมนี้มีผู้สมัครเต็มแล้ว"
    return None


# --------------------------- เลือกผู้รับ ---------------------------
def collect_at_risk_students(
    session: Session,
    *,
    threshold: Optional[float] = None,
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
) -> list[AtRiskStudent]:
    """นิสิต (ที่ยังศึกษาอยู่) ซึ่งชั่วโมงรวมต่ำกว่า ``threshold`` % ของเกณฑ์

    อ่านจาก ``gold_student_hours`` ซึ่งมีหนึ่งแถวต่อ นิสิต × หมวดชั่วโมง จึงได้ทั้ง
    ยอดรวมและรายละเอียดว่าขาดหมวดไหนในคิวรีเดียว
    """
    limit = settings.notify_at_risk_threshold if threshold is None else threshold

    clauses = ["d.status = 'active'"]
    params: dict = {}
    if faculty:
        clauses.append("d.faculty = :faculty")
        params["faculty"] = faculty
    if year_level is not None:
        clauses.append("d.year_level = :year_level")
        params["year_level"] = year_level

    rows = session.execute(
        text(
            "SELECT g.student_key, g.student_code, g.full_name, g.faculty, g.year_level, "
            "g.category_key, g.category_name, g.required_hours, g.earned_hours "
            "FROM gold_student_hours g "
            "JOIN gold_dim_student d ON d.student_key = g.student_key "
            f"WHERE {' AND '.join(clauses)} "
            "ORDER BY g.student_key, g.category_key"
        ),
        params,
    ).all()

    people = {key: (code, name, fac, year) for key, code, name, fac, year, *_ in rows}
    progress = progress_by_student(
        (key, item_key, item_name, required, earned)
        for key, _c, _n, _f, _y, item_key, item_name, required, earned in rows
    )

    at_risk = []
    for key, p in progress.items():
        # ไม่มีเกณฑ์ (ยังไม่ได้ตั้งหมวดชั่วโมง/ชุดเกณฑ์) = ยังตัดสินไม่ได้ว่าใครเสี่ยง ข้ามไป
        if p.required_hours <= 0:
            continue
        code, name, fac, year = people[key]
        student = AtRiskStudent(
            student_key=key,
            student_code=code,
            full_name=name,
            faculty=fac,
            year_level=year,
            # ชั่วโมงที่นับเข้าเกณฑ์ (ส่วนเกินของรายการหนึ่งไม่ชดเชยอีกรายการ) — กติกาเดียวกับแดชบอร์ด
            earned_hours=p.counted_hours,
            required_hours=p.required_hours,
            gaps=tuple(CategoryGap(g.name, g.earned_hours, g.required_hours) for g in p.gaps),
        )
        if student.percent < limit:
            at_risk.append(student)

    # เสี่ยงที่สุดขึ้นก่อน เหมือนลำดับบนแดชบอร์ด
    at_risk.sort(key=lambda s: (s.percent, s.earned_hours))
    return at_risk


def collect_activity_recipients(
    session: Session,
    activity_id: int,
    *,
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
) -> list[Student]:
    """นิสิตที่ยังศึกษาอยู่และ **ยังไม่ได้สมัคร** กิจกรรมนี้

    คนที่สมัครแล้วไม่ควรได้อีเมลชวนสมัครซ้ำ — เป็นสิ่งแรกที่ทำให้คนกดยกเลิกรับข่าว
    """
    registered = select(Participation.student_id).where(Participation.activity_id == activity_id)
    query = select(Student).where(
        Student.status == "active",
        Student.id.not_in(registered),
    )
    if faculty:
        query = query.where(Student.faculty == faculty)
    if year_level is not None:
        query = query.where(Student.year_level == year_level)
    return list(session.exec(query.order_by(Student.student_id)).all())


# --------------------------- ส่งจริง ---------------------------
def _send_all(sender: EmailSender, messages: list[EmailMessage], subject: str) -> NotificationReport:
    """ส่งทีละฉบับ ฉบับที่ล้มไม่ทำให้ที่เหลือหยุดส่ง

    การแจ้งเตือนเป็นงาน "ยิงแล้วลืม" — ถ้าปล่อย exception ออกไป ผู้ดูแลจะเห็นแค่
    500 โดยไม่รู้ว่าส่งไปแล้วกี่คน จึงเก็บผลรายฉบับแล้วสรุปกลับไปแทน
    """
    report = NotificationReport(subject=subject)
    for message in messages:
        try:
            sender.send(message)
        except Exception:  # noqa: BLE001 — ปลายทางล่มหนึ่งราย ไม่ควรล้มทั้งรอบ
            logger.warning("ส่งอีเมลถึง %s ไม่สำเร็จ", message.to, exc_info=True)
            report.failed += 1
            report.failed_recipients.append(message.to)
        else:
            report.sent += 1
            report.recipients.append(message.to)
    return report


def send_at_risk_notifications(
    session: Session,
    sender: EmailSender,
    *,
    threshold: Optional[float] = None,
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
) -> NotificationReport:
    students = collect_at_risk_students(
        session, threshold=threshold, faculty=faculty, year_level=year_level
    )
    messages = [build_at_risk_message(s) for s in students]
    return _send_all(sender, messages, subject="แจ้งเตือนนิสิตกลุ่มเสี่ยง")


def send_activity_announcement(
    session: Session,
    sender: EmailSender,
    activity: Activity,
    *,
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
) -> NotificationReport:
    category_name = None
    if activity.subcategory_id:
        subcategory = session.get(HourSubcategory, activity.subcategory_id)
        if subcategory:
            category = subcategory.category
            category_name = (
                f"{category.name} › {subcategory.name}" if category else subcategory.name
            )
    if category_name is None:
        # กิจกรรมชุดเกณฑ์ใหม่ไม่มีหมวดเดิม — บอกรายการเกณฑ์ที่นับให้แทน
        names = session.exec(
            select(Requirement.name)
            .join(ActivityRequirement, ActivityRequirement.requirement_id == Requirement.id)
            .where(ActivityRequirement.activity_id == activity.id)
            .order_by(Requirement.id)
        ).all()
        category_name = " · ".join(names) or None

    registered = len(
        session.exec(
            select(Participation).where(Participation.activity_id == activity.id)
        ).all()
    )
    available = max(activity.max_participants - registered, 0)

    recipients = collect_activity_recipients(
        session, activity.id, faculty=faculty, year_level=year_level
    )
    messages = [
        build_activity_message(
            student_name=s.full_name,
            student_code=s.student_id,
            activity=activity,
            category_name=category_name,
            available_seats=available,
        )
        for s in recipients
    ]
    return _send_all(sender, messages, subject=f"ประชาสัมพันธ์กิจกรรม {activity.name}")
