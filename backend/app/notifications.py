"""แจ้งเตือนทางอีเมล (ข้อ 6.4) — เลือกผู้รับ + เขียนเนื้อความ

สองแบบตามที่กำหนดไว้:

1. **นิสิตกลุ่มเสี่ยง** — ชั่วโมงสะสมยังไม่ถึงเกณฑ์ อ่านจาก ``gold_student_hours``
   (Gold Layer) เหมือนที่แดชบอร์ดใช้ รายชื่อที่ได้รับอีเมลจึงตรงกับรายชื่อบน
   หน้าแดชบอร์ดเสมอ ไม่ใช่คนละชุดเพราะคำนวณคนละที่
2. **ประชาสัมพันธ์กิจกรรม** — กิจกรรมที่อนุมัติแล้ว ยังไม่ถึงวันจัด และยังไม่เต็ม
   ส่งถึงนิสิตที่ยังไม่ได้สมัครกิจกรรมนั้น
3. **เตือนกิจกรรมพรุ่งนี้** — กิจกรรมที่จะจัด "วันพรุ่งนี้" ตามเวลาไทย ส่งถึงนิสิตที่
   สมัครไว้แล้ว (ตรงข้ามกับข้อ 2 ซึ่งส่งถึงคนที่ *ยัง* ไม่ได้สมัคร)
4. **ยืนยันการสมัคร** — ส่งทันทีหลังนิสิตสมัครสำเร็จ ถ้ากิจกรรมจัดภายในวันพรุ่งนี้ (เวลาไทย)
   ฉบับนี้นับเป็นการเตือนแล้ว (``participation.reminder_sent_at``) ข้อ 3 จึงไม่ส่งซ้ำ

ฟังก์ชันเลือกผู้รับกับฟังก์ชันเขียนเนื้อความแยกจากกัน และตัวเขียนเนื้อความเป็น
pure function ทั้งหมด — เทสต์ข้อความภาษาไทยได้โดยไม่ต้องมีฐานข้อมูล

**ที่อยู่อีเมลมาจากคอลัมน์ ``student.email`` เท่านั้น** ไม่เดาจากรหัสนิสิตอีกต่อไป —
ที่อยู่ที่เดาเอาแล้วส่งไม่ถึงทำให้รายงาน "ส่งสำเร็จ" โกหกผู้ดูแล นิสิตที่ยังไม่ระบุอีเมล
(``email`` เป็น NULL) จะถูก **ข้าม** และนับไว้ใน :attr:`NotificationReport.skipped`
พร้อมรายชื่อรหัสนิสิต เพื่อให้ผู้ดูแลรู้ว่าต้องตามกรอกอีเมลให้ใครบ้าง
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, time, timedelta
from typing import Callable, Iterable, Optional, TypeVar

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
    # None = ยังไม่ระบุอีเมล -> ส่งไม่ได้ ต้องถูกข้ามก่อนเขียนเนื้อความ
    email: Optional[str] = None

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
    # คนที่ยังไม่ระบุอีเมล — ไม่ได้ล้มเหลว แต่ก็ไม่ได้รับ จึงต้องแยกจาก failed
    # ไม่งั้นผู้ดูแลอ่านรายงานแล้วเข้าใจว่าครอบคลุมนิสิตครบทุกคน
    skipped: int = 0
    recipients: list[str] = field(default_factory=list)
    failed_recipients: list[str] = field(default_factory=list)
    # เก็บเป็น "รหัสนิสิต" ไม่ใช่ที่อยู่อีเมล เพราะคนกลุ่มนี้ไม่มีที่อยู่ให้เก็บ
    skipped_students: list[str] = field(default_factory=list)
    # True = แค่ดูว่าจะส่งหาใคร ยังไม่ได้ส่งจริง ``recipients`` คือ "คนที่จะได้รับ"
    # และ ``sent`` เป็น 0 เสมอ — มีธงนี้ไว้ไม่ให้ผู้ดูแลอ่าน sent=0 แล้วเข้าใจว่าส่งล้มเหลว
    dry_run: bool = False


# --------------------------- ตัวช่วยเล็ก ๆ ---------------------------
def format_hours(value: float) -> str:
    """4.0 → "4" แต่ 4.5 ยังเป็น "4.5" — เลขกลม ๆ ในอีเมลอ่านง่ายกว่า"""
    return str(int(value)) if float(value).is_integer() else str(value)


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
    """อีเมลเตือนนิสิตที่ชั่วโมงยังไม่ครบเกณฑ์

    เรียกได้เฉพาะนิสิตที่มีอีเมลแล้ว — ผู้เรียกต้องกรองคนที่ยังไม่ระบุออกไปก่อน
    (ดู :func:`partition_by_email`) ที่นี่จึงยืนยันไว้แทนที่จะปล่อยให้ ``to=None``
    ไหลลงไปถึงตัวส่งแล้วค่อยระเบิดตอนนั้น
    """
    if not student.email:
        raise ValueError(f"นิสิต {student.student_code} ยังไม่ระบุอีเมล จึงเขียนอีเมลถึงไม่ได้")
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
        to=student.email,
        subject=f"[แจ้งเตือน] ชั่วโมงกิจกรรมของคุณยังขาดอีก {missing} ชั่วโมง",
        body="\n".join(lines),
    )


def build_activity_message(
    *,
    student_name: str,
    student_email: str,
    activity: Activity,
    category_name: Optional[str],
    available_seats: int,
) -> EmailMessage:
    """อีเมลประชาสัมพันธ์กิจกรรมที่กำลังเปิดรับสมัคร

    ``student_email`` ต้องมีค่าแล้ว — คนที่ยังไม่ระบุถูกกรองออกตั้งแต่ชั้นเลือกผู้รับ
    """
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
        to=student_email,
        subject=f"[ประชาสัมพันธ์] ขอเชิญเข้าร่วมกิจกรรม {activity.name}",
        body="\n".join(lines),
    )


def build_activity_reminder_message(
    *,
    student_name: str,
    student_email: str,
    activity: Activity,
) -> EmailMessage:
    """อีเมลเตือนล่วงหน้า 1 วันสำหรับกิจกรรมที่นิสิตสมัครไว้แล้ว

    คนอ่านคือคนที่ "สมัครไว้เมื่อหลายสัปดาห์ก่อนแล้วลืม" ข้อมูลที่ต้องใช้ในเช้าวันงาน
    จึงอยู่ครบในฉบับเดียว: เวลา สถานที่ และชั่วโมงที่จะได้ โดยไม่ต้องเปิดเว็บไปหาเอง
    """
    lines = [
        f"เรียน {student_name}",
        "",
        f"พรุ่งนี้เป็นวันจัดกิจกรรม “{activity.name}” ที่คุณสมัครเข้าร่วมไว้",
        "",
        f"  วันเวลา       : {format_thai_datetime(activity.start_at)}",
        f"  สถานที่       : {activity.location}",
        f"  ชั่วโมงที่จะได้รับ : {format_hours(activity.hours)} ชั่วโมง",
        "",
        "กรุณาไปถึงก่อนเวลาเริ่มและเช็กอินหน้างานเพื่อให้ระบบบันทึกชั่วโมงให้ครบ",
        "",
        "ดูรายละเอียดกิจกรรมได้ที่",
        f"  {app_url()}",
        _SIGNATURE,
    ]

    return EmailMessage(
        to=student_email,
        subject=f"[เตือนล่วงหน้า] พรุ่งนี้มีกิจกรรม {activity.name}",
        body="\n".join(lines),
    )


@dataclass(frozen=True)
class RegistrationConfirmation:
    """ข้อมูลของอีเมลยืนยันการสมัคร — snapshot ค่าล้วนตอนสมัคร

    อีเมลส่งเป็นงานเบื้องหลังหลังตอบ response ไปแล้ว ตอนนั้น session ของ request ปิดไปแล้ว
    จึงเก็บเป็นค่าธรรมดา ไม่อ้างอ็อบเจกต์ ORM ที่หลุดจาก session
    """

    to: str
    student_name: str
    activity_name: str
    start_at: datetime  # เวลาไทยแบบไม่มีโซน (เหมือน activity.start_at)
    location: str
    hours: float
    # True = กิจกรรมเริ่มภายในช่วงที่อีเมลนี้นับเป็นการเตือนแล้ว ตัวเตือน 1 วันจะไม่ส่งซ้ำ
    counts_as_reminder: bool = False


def registration_counts_as_reminder(start_at: datetime, registered_at: Optional[datetime] = None) -> bool:
    """กิจกรรมจัดภายใน "วันพรุ่งนี้" ตามเวลาไทย (นับจากวันที่สมัคร) → อีเมลยืนยันนับเป็นการเตือนแล้ว

    ฐานเดียวกับตัวเตือน (:func:`tomorrow_window`): รอบเย็นของวันนี้เตือนกิจกรรมของพรุ่งนี้ — สมัครกิจกรรม
    ของวันนี้/พรุ่งนี้แล้วอีเมลเตือนจะตามมาภายในไม่กี่ชั่วโมง (หรือรอบนั้นผ่านไปแล้ว) จึงไม่ต้องส่งอีกฉบับ
    กิจกรรมตั้งแต่มะรืนขึ้นไปยังได้อีเมลเตือนตามปกติ

    เดิมใช้ "≤ 24 ชม." ซึ่งพลาดกรณีสมัคร 10:00 น. สำหรับกิจกรรมพรุ่งนี้ 15:00 น. (เหลือ 29 ชม.) — ได้อีเมล
    ยืนยันแล้วอีเมลเตือนตามมาตอน 18:00 น. ห่างกันไม่กี่ชั่วโมง

    ทั้งสองค่าเป็นเวลาไทยแบบไม่มีโซน (``activity.start_at`` / :func:`now_th_naive`) — เทียบกับ
    ``utcnow()`` จะคลาด 7 ชม. (เคยเป็นบั๊กของการสมัครมาแล้ว)
    """
    _, end_of_tomorrow = tomorrow_window(registered_at)
    return start_at < end_of_tomorrow


def build_registration_confirmation_message(confirmation: RegistrationConfirmation) -> EmailMessage:
    """อีเมลยืนยันการสมัคร — รายละเอียดที่ต้องใช้วันงานครบในฉบับเดียว เหมือนอีเมลเตือน"""
    lines = [
        f"เรียน {confirmation.student_name}",
        "",
        f"ระบบได้รับการสมัครเข้าร่วมกิจกรรม “{confirmation.activity_name}” ของคุณเรียบร้อยแล้ว",
        "",
        f"  วันเวลา       : {format_thai_datetime(confirmation.start_at)}",
        f"  สถานที่       : {confirmation.location}",
        f"  ชั่วโมงที่จะได้รับ : {format_hours(confirmation.hours)} ชั่วโมง",
        "",
    ]
    if confirmation.counts_as_reminder:
        lines += [
            "กิจกรรมนี้จัดภายในวันพรุ่งนี้ ระบบจะไม่ส่งอีเมลเตือนซ้ำอีก",
            "",
        ]
    lines += [
        "กรุณาไปถึงก่อนเวลาเริ่มและเช็กอินหน้างาน ชั่วโมงจะนับเมื่อส่งหลักฐานและเจ้าหน้าที่อนุมัติ",
        "",
        "ดูรายละเอียดกิจกรรมได้ที่",
        f"  {app_url()}",
        _SIGNATURE,
    ]
    return EmailMessage(
        to=confirmation.to,
        subject=f"[ยืนยันการสมัคร] {confirmation.activity_name}",
        body="\n".join(lines),
    )


def send_registration_confirmation(sender: EmailSender, confirmation: RegistrationConfirmation) -> bool:
    """งานเบื้องหลังหลังสมัคร — ส่งล้มแค่ log ไม่โยนต่อ (การสมัครสำเร็จไปแล้ว ต้องไม่กลายเป็น error)"""
    try:
        sender.send(build_registration_confirmation_message(confirmation))
    except Exception:  # noqa: BLE001 — SMTP ล่มต้องไม่ย้อนมาทำให้การสมัครดูเหมือนล้ม
        logger.warning("ส่งอีเมลยืนยันการสมัครถึง %s ไม่สำเร็จ", confirmation.to, exc_info=True)
        return False
    return True


def tomorrow_window(now: Optional[datetime] = None) -> tuple[datetime, datetime]:
    """ช่วงเวลา ``[เริ่ม, สิ้นสุด)`` ของ "วันพรุ่งนี้" ตามเวลาไทย

    ``activity.start_at`` เก็บเป็นเวลาไทยแบบไม่มีโซนอยู่แล้ว (ดู ``app/timeutil.py``)
    สิ่งที่ต้องอิงเวลาไทยคือ "วันนี้วันอะไร" — ถ้าคำนวณจากเวลา UTC ตอนหัวค่ำของไทย
    วันจะเลื่อนไปหนึ่งวัน แล้วอีเมลเตือนจะออกผิดวันทั้งรอบ

    คืนเป็นช่วงครึ่งเปิดเพื่อให้กรองที่ฐานข้อมูลได้ตรง ๆ (ใช้ index ของ start_at)
    แทนการดึงกิจกรรมทั้งหมดมาเทียบวันที่ในไพทอน
    """
    today = (now or now_th_naive()).date()
    start = datetime.combine(today + timedelta(days=1), time.min)
    return start, start + timedelta(days=1)


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
            "d.email, g.category_key, g.category_name, g.required_hours, g.earned_hours "
            "FROM gold_student_hours g "
            "JOIN gold_dim_student d ON d.student_key = g.student_key "
            f"WHERE {' AND '.join(clauses)} "
            "ORDER BY g.student_key, g.category_key"
        ),
        params,
    ).all()

    people = {key: (code, name, fac, year, email) for key, code, name, fac, year, email, *_ in rows}
    progress = progress_by_student(
        (key, item_key, item_name, required, earned)
        for key, _c, _n, _f, _y, _e, item_key, item_name, required, earned in rows
    )

    at_risk = []
    for key, p in progress.items():
        # ไม่มีเกณฑ์ (ยังไม่ได้ตั้งหมวดชั่วโมง/ชุดเกณฑ์) = ยังตัดสินไม่ได้ว่าใครเสี่ยง ข้ามไป
        if p.required_hours <= 0:
            continue
        code, name, fac, year, email = people[key]
        student = AtRiskStudent(
            student_key=key,
            student_code=code,
            full_name=name,
            faculty=fac,
            year_level=year,
            email=email,
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


def collect_tomorrow_activities(
    session: Session, *, now: Optional[datetime] = None
) -> list[tuple[Activity, list[Student]]]:
    """กิจกรรมของพรุ่งนี้ พร้อมนิสิตที่สมัครไว้ของแต่ละรายการ

    เงื่อนไขของกิจกรรมตรงกับ "กิจกรรมที่นิสิตเห็นว่ายังจัดอยู่จริง":
    อนุมัติแล้ว และไม่ถูกซ่อน (ซ่อน = ถูกยกเลิกในสายตานิสิต ดู routers/participations.py)

    ผู้รับคือคนที่ยังมีแถว ``participation`` อยู่ — การยกเลิกสมัครลบแถวทิ้ง ไม่ได้ทำเป็น
    สถานะ จึงไม่ต้องกรองสถานะเพิ่ม แถวที่ยังอยู่ = ยังไม่ยกเลิก

    ข้ามแถวที่ ``reminder_sent_at`` ตั้งแล้ว — เตือนไปแล้ว หรืออีเมลยืนยันการสมัครทำหน้าที่เตือนแทน
    """
    start, end = tomorrow_window(now)
    activities = session.exec(
        select(Activity)
        .where(
            Activity.approval_status == ApprovalStatus.approved,
            Activity.is_hidden.is_(False),
            Activity.start_at >= start,
            Activity.start_at < end,
        )
        .order_by(Activity.start_at, Activity.id)
    ).all()

    result = []
    for activity in activities:
        students = session.exec(
            select(Student)
            .join(Participation, Participation.student_id == Student.id)
            .where(
                Participation.activity_id == activity.id,
                Participation.reminder_sent_at.is_(None),
            )
            .order_by(Student.student_id)
        ).all()
        if students:
            result.append((activity, list(students)))
    return result


# --------------------------- ส่งจริง ---------------------------
T = TypeVar("T")


def partition_by_email(
    people: Iterable[T], *, email_of, code_of
) -> tuple[list[T], list[str]]:
    """แยกผู้รับออกเป็น (คนที่มีอีเมล, รหัสนิสิตของคนที่ยังไม่ระบุ)

    เป็น pure function เพื่อให้กติกา "ใครถูกข้าม" มีที่เดียว ทั้งอีเมลกลุ่มเสี่ยงและ
    อีเมลประชาสัมพันธ์ใช้ตัวเดียวกัน — ไม่ใช่ต่างคนต่างเช็กแล้วหลุดไปข้างหนึ่ง
    """
    sendable: list[T] = []
    skipped: list[str] = []
    for person in people:
        if (email_of(person) or "").strip():
            sendable.append(person)
        else:
            skipped.append(code_of(person))
    return sendable, skipped


def _send_all(
    sender: EmailSender,
    messages: list[EmailMessage],
    subject: str,
    skipped_students: Optional[list[str]] = None,
    on_sent: Optional[Callable[[int], None]] = None,
) -> NotificationReport:
    """ส่งทีละฉบับ ฉบับที่ล้มไม่ทำให้ที่เหลือหยุดส่ง

    การแจ้งเตือนเป็นงาน "ยิงแล้วลืม" — ถ้าปล่อย exception ออกไป ผู้ดูแลจะเห็นแค่
    500 โดยไม่รู้ว่าส่งไปแล้วกี่คน จึงเก็บผลรายฉบับแล้วสรุปกลับไปแทน

    ``on_sent(i)`` ถูกเรียกหลังฉบับที่ ``i`` ส่งสำเร็จ — ให้ผู้เรียกบันทึกว่าส่งถึงแล้วเฉพาะฉบับที่ออกจริง
    """
    report = NotificationReport(subject=subject)
    if skipped_students:
        report.skipped = len(skipped_students)
        report.skipped_students = list(skipped_students)
    for index, message in enumerate(messages):
        try:
            sender.send(message)
        except Exception:  # noqa: BLE001 — ปลายทางล่มหนึ่งราย ไม่ควรล้มทั้งรอบ
            logger.warning("ส่งอีเมลถึง %s ไม่สำเร็จ", message.to, exc_info=True)
            report.failed += 1
            report.failed_recipients.append(message.to)
        else:
            report.sent += 1
            report.recipients.append(message.to)
            if on_sent is not None:
                on_sent(index)
    return report


def _mark_reminded(session: Session, targets: list[tuple[int, int]]) -> None:
    """ตั้ง ``reminder_sent_at`` ให้ (activity_id, student_id) ที่ส่งเตือนสำเร็จ — รอบถัดไปจะไม่ส่งซ้ำ

    อีเมลออกไปแล้วเรียกคืนไม่ได้ บันทึกล้มจึงแค่ log (รายงานผลส่งยังต้องกลับถึงผู้ดูแล)
    """
    if not targets:
        return
    stamp = datetime.utcnow()
    try:
        for activity_id, student_id in targets:
            participation = session.exec(
                select(Participation).where(
                    Participation.activity_id == activity_id,
                    Participation.student_id == student_id,
                    Participation.reminder_sent_at.is_(None),
                )
            ).first()
            if participation is not None:
                participation.reminder_sent_at = stamp
                session.add(participation)
        session.commit()
    except Exception:  # noqa: BLE001
        session.rollback()
        logger.exception("บันทึก reminder_sent_at ไม่สำเร็จ — รอบถัดไปอาจเตือนซ้ำ %d ราย", len(targets))


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
    sendable, skipped = partition_by_email(
        students, email_of=lambda s: s.email, code_of=lambda s: s.student_code
    )
    if skipped:
        logger.info("ข้ามนิสิตกลุ่มเสี่ยงที่ยังไม่ระบุอีเมล %d คน", len(skipped))
    messages = [build_at_risk_message(s) for s in sendable]
    return _send_all(
        sender, messages, subject="แจ้งเตือนนิสิตกลุ่มเสี่ยง", skipped_students=skipped
    )


def send_activity_reminders(
    session: Session,
    sender: EmailSender,
    *,
    now: Optional[datetime] = None,
    dry_run: bool = False,
) -> NotificationReport:
    """เตือนนิสิตที่สมัครกิจกรรมของพรุ่งนี้ไว้ — หนึ่งฉบับต่อ นิสิต × กิจกรรม

    คนที่สมัครสองกิจกรรมในวันเดียวกันจะได้สองฉบับโดยตั้งใจ: รวบเป็นฉบับเดียวแล้ว
    เวลา/สถานที่ของแต่ละงานจะปนกันในอีเมลเดียว ซึ่งอ่านพลาดง่ายกว่าตอนรีบ ๆ ตอนเช้า

    ``dry_run=True`` = ไม่ส่งอะไรเลย แต่คืนรายชื่อผู้รับที่จะได้รับ ให้ผู้ดูแลตรวจก่อน
    กดส่งจริง (อีเมลถึงนิสิตเป็นสิ่งที่เรียกคืนไม่ได้)

    ฉบับที่ส่งสำเร็จจะตั้ง ``reminder_sent_at`` — สั่งซ้ำ (รอบอัตโนมัติ + กดส่งเอง) ไม่เตือนคนเดิมซ้ำ
    """
    subject = "เตือนกิจกรรมที่จะจัดพรุ่งนี้"
    pairs = collect_tomorrow_activities(session, now=now)

    messages: list[EmailMessage] = []
    targets: list[tuple[int, int]] = []  # (activity_id, student_id) ตามลำดับ messages
    skipped: list[str] = []
    for activity, students in pairs:
        sendable, without_email = partition_by_email(
            students, email_of=lambda s: s.email, code_of=lambda s: s.student_id
        )
        skipped.extend(without_email)
        for s in sendable:
            messages.append(
                build_activity_reminder_message(
                    student_name=s.full_name,
                    student_email=s.email,
                    activity=activity,
                )
            )
            targets.append((activity.id, s.id))

    if skipped:
        logger.info("ข้ามผู้รับอีเมลเตือนกิจกรรมที่ยังไม่ระบุอีเมล %d ราย", len(skipped))

    if dry_run:
        # ไม่แตะ sender เลย เพื่อให้ dry-run เป็นการอ่านอย่างเดียวจริง ๆ
        return NotificationReport(
            subject=subject,
            skipped=len(skipped),
            recipients=[m.to for m in messages],
            skipped_students=skipped,
            dry_run=True,
        )
    sent_targets: list[tuple[int, int]] = []
    report = _send_all(
        sender,
        messages,
        subject=subject,
        skipped_students=skipped,
        on_sent=lambda index: sent_targets.append(targets[index]),
    )
    _mark_reminded(session, sent_targets)
    return report


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
    sendable, skipped = partition_by_email(
        recipients, email_of=lambda s: s.email, code_of=lambda s: s.student_id
    )
    if skipped:
        logger.info("ข้ามผู้รับประชาสัมพันธ์ที่ยังไม่ระบุอีเมล %d คน", len(skipped))
    messages = [
        build_activity_message(
            student_name=s.full_name,
            student_email=s.email,
            activity=activity,
            category_name=category_name,
            available_seats=available,
        )
        for s in sendable
    ]
    return _send_all(
        sender,
        messages,
        subject=f"ประชาสัมพันธ์กิจกรรม {activity.name}",
        skipped_students=skipped,
    )
