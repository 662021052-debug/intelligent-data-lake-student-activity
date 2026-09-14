"""endpoint สั่งส่งอีเมลแจ้งเตือน (ข้อ 6.4) — admin เท่านั้น

ทั้งสอง endpoint เป็นการ "สั่งส่งเดี๋ยวนี้" ด้วยมือ ส่วนรอบอัตโนมัติรายวันอยู่ที่
``app/scheduler.py`` ซึ่งเรียกฟังก์ชันชุดเดียวกันใน ``app/notifications.py``
เนื้อความและเกณฑ์ผู้รับจึงตรงกันเสมอ ไม่ว่าจะส่งด้วยมือหรือให้ระบบส่งเอง
"""

import logging
import re
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlmodel import Session, select

from app.auth import require_admin
from app.config import settings
from app.database import get_session
from app.email import (
    EmailMessage,
    EmailSender,
    email_backend_name,
    explain_email_error,
    get_email_sender,
)
from app.models import EMAIL_PATTERN, Activity, Participation
from app.notifications import (
    NotificationReport,
    announcement_blocker,
    send_activity_announcement,
    send_activity_reminders,
    send_at_risk_notifications,
)
from app.timeutil import now_th_naive

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/notifications",
    tags=["notifications"],
    dependencies=[Depends(require_admin)],  # admin only -> non-admin gets 403
)


class NotificationResult(BaseModel):
    """สรุปผลการส่งกลับไปให้ผู้ดูแลเห็นว่าถึงใครแล้วบ้าง"""

    subject: str
    sent: int
    failed: int
    # นิสิตที่เข้าเงื่อนไขผู้รับแต่ยังไม่ได้ระบุอีเมล จึงไม่ได้ถูกส่งถึง — ผู้ดูแลจะได้รู้ว่า
    # ยอด sent ไม่ได้แปลว่าครอบคลุมทุกคน แล้วตามไปกรอกอีเมลให้คนที่ขาดได้
    skipped: int
    # ตัดรายชื่อไว้ไม่ให้ตอบกลับยาวเป็นพัน (นิสิต 100+ คน) แต่ยังพอให้ยืนยันได้ว่า
    # ส่งถูกกลุ่ม — จำนวนจริงอยู่ที่ sent/failed/skipped
    recipients: list[str]
    failed_recipients: list[str]
    # เป็น "รหัสนิสิต" ไม่ใช่ที่อยู่อีเมล — คนกลุ่มนี้ยังไม่มีที่อยู่ให้แสดง
    skipped_students: list[str]
    # true = ยังไม่ได้ส่ง recipients คือ "คนที่จะได้รับ" และ sent เป็น 0 เสมอ
    dry_run: bool = False


MAX_LISTED_RECIPIENTS = 50


class TestEmailResult(BaseModel):
    """ผลส่งอีเมลทดสอบ — ok=false พร้อม error_type/reason บอกว่าล้มที่ขั้นไหน"""

    ok: bool
    to: str
    backend: str  # smtp = ส่งออกจริง · stub = ไม่ได้ส่งจริง
    smtp_host: Optional[str] = None
    smtp_port: Optional[int] = None
    error_type: Optional[str] = None
    reason: str


def _to_result(report: NotificationReport) -> NotificationResult:
    return NotificationResult(
        subject=report.subject,
        sent=report.sent,
        failed=report.failed,
        skipped=report.skipped,
        recipients=report.recipients[:MAX_LISTED_RECIPIENTS],
        failed_recipients=report.failed_recipients[:MAX_LISTED_RECIPIENTS],
        skipped_students=report.skipped_students[:MAX_LISTED_RECIPIENTS],
        dry_run=report.dry_run,
    )


@router.post(
    "/test-email",
    response_model=TestEmailResult,
    responses={
        502: {"model": TestEmailResult, "description": "ต่อ/ส่งผ่าน SMTP ไม่สำเร็จ"},
        503: {"model": TestEmailResult, "description": "ยังไม่ได้ตั้งค่า SMTP (ตัวส่งเป็น stub)"},
    },
)
def send_test_email(
    to: str = Query(..., description="ที่อยู่อีเมลปลายทางของฉบับทดสอบ"),
    sender: EmailSender = Depends(get_email_sender),
):
    """ส่งอีเมลทดสอบ 1 ฉบับ เพื่อยืนยันว่าตั้งค่า SMTP ถูกและส่งออกได้จริง

    config ทั้งหมดมาจาก env (EMAIL_BACKEND / SMTP_*) ผ่านตัวส่งตัวเดียวกับที่
    แจ้งเตือนจริงใช้ — ถ้าฉบับนี้ผ่าน อีเมลแจ้งเตือนก็ส่งออกได้
    """
    to = to.strip()
    if not re.fullmatch(EMAIL_PATTERN, to):
        raise HTTPException(status_code=422, detail="รูปแบบอีเมลปลายทางไม่ถูกต้อง")

    backend = email_backend_name(sender)
    base = {
        "to": to,
        "backend": backend,
        "smtp_host": settings.smtp_host or None,
        "smtp_port": settings.smtp_port,
    }
    if backend != "smtp":
        result = TestEmailResult(
            ok=False,
            error_type="not_configured",
            reason=(
                "ไม่ได้ส่งจริง: ตัวส่งเป็น stub "
                f"(EMAIL_BACKEND={settings.email_backend}, "
                f"SMTP_HOST {'ตั้งแล้ว' if settings.smtp_host else 'ว่าง'}) — "
                "ตั้ง EMAIL_BACKEND=smtp กับ SMTP_HOST และส่ง env เข้าคอนเทนเนอร์"
            ),
            **base,
        )
        return JSONResponse(status_code=503, content=result.model_dump())

    sent_at = now_th_naive().strftime("%Y-%m-%d %H:%M")
    message = EmailMessage(
        to=to,
        subject="[ทดสอบ] อีเมลจากระบบกิจกรรมพัฒนานิสิต",
        body=(
            "นี่คืออีเมลทดสอบการตั้งค่า SMTP ของระบบกิจกรรมพัฒนานิสิต\n\n"
            f"ส่งเมื่อ {sent_at} (เวลาไทย) ผ่าน {settings.smtp_host}:{settings.smtp_port}\n"
            "ถ้าได้รับฉบับนี้ แปลว่าอีเมลแจ้งเตือนของระบบส่งออกได้แล้ว ไม่ต้องตอบกลับ\n"
        ),
    )
    try:
        sender.send(message)
    except Exception as exc:  # noqa: BLE001 - ทุกความล้มเหลวต้องกลับไปบอกผู้ดูแล
        error_type, reason = explain_email_error(exc)
        logger.warning("test email to %s failed: %s (%s)", to, error_type, type(exc).__name__)
        result = TestEmailResult(ok=False, error_type=error_type, reason=reason, **base)
        return JSONResponse(status_code=502, content=result.model_dump())

    return TestEmailResult(
        ok=True,
        reason=f"ส่งผ่าน {settings.smtp_host}:{settings.smtp_port} สำเร็จ — เซิร์ฟเวอร์รับอีเมลแล้ว",
        **base,
    )


@router.post("/at-risk", response_model=NotificationResult)
def notify_at_risk(
    threshold: Optional[float] = Query(
        None, ge=0, le=100, description="ต่ำกว่ากี่ % ของเกณฑ์ถือว่าเสี่ยง (ไม่ระบุ = ใช้ค่าจาก .env)"
    ),
    faculty: Optional[str] = None,
    year_level: Optional[int] = Query(None, ge=1, le=8, description="ส่งเฉพาะชั้นปีนี้"),
    session: Session = Depends(get_session),
    sender: EmailSender = Depends(get_email_sender),
):
    """ส่งอีเมลเตือนนิสิตที่ชั่วโมงสะสมยังไม่ถึงเกณฑ์

    กรองตามคณะ/ชั้นปีได้ เพื่อยิงเฉพาะกลุ่มที่ "ใกล้เส้นตาย" จริง ๆ เช่นปีสุดท้าย
    (สคีมายังไม่มีวันเส้นตายของแต่ละรุ่นให้คำนวณอัตโนมัติ)
    """
    report = send_at_risk_notifications(
        session, sender, threshold=threshold, faculty=faculty, year_level=year_level
    )
    return _to_result(report)


@router.post("/activity-reminders", response_model=NotificationResult)
def notify_activity_reminders(
    dry_run: bool = Query(
        False,
        description="true = ดูว่าจะส่งถึงใครบ้างโดยยังไม่ส่งจริง (recipients คือคนที่จะได้รับ)",
    ),
    session: Session = Depends(get_session),
    sender: EmailSender = Depends(get_email_sender),
):
    """เตือนนิสิตที่สมัครไว้ ว่าพรุ่งนี้มีกิจกรรม (ส่งล่วงหน้า 1 วัน)

    ปกติงานตั้งเวลารายวันเป็นคนเรียก (``app/scheduler.py``) endpoint นี้มีไว้ให้ผู้ดูแล
    สั่งเองเมื่อรอบอัตโนมัติปิดอยู่หรือพลาดรอบไป — และให้ cron ภายนอกเรียกได้ด้วย

    ลองด้วย ``?dry_run=true`` ก่อนได้เสมอ: อีเมลที่ส่งออกไปแล้วเรียกคืนไม่ได้ และ
    "วันพรุ่งนี้" คิดตามเวลาไทย ถ้าสั่งผิดรอบก็ไปโผล่ผิดวันทั้งชุด
    """
    report = send_activity_reminders(session, sender, dry_run=dry_run)
    return _to_result(report)


@router.post("/activity/{activity_id}", response_model=NotificationResult)
def notify_activity(
    activity_id: int,
    faculty: Optional[str] = None,
    year_level: Optional[int] = Query(None, ge=1, le=8),
    session: Session = Depends(get_session),
    sender: EmailSender = Depends(get_email_sender),
):
    """ประชาสัมพันธ์กิจกรรมที่กำลังเปิดรับสมัคร ถึงนิสิตที่ยังไม่ได้สมัคร"""
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")

    participant_count = len(
        session.exec(select(Participation).where(Participation.activity_id == activity_id)).all()
    )
    blocker = announcement_blocker(activity, participant_count)
    if blocker:
        raise HTTPException(status_code=400, detail=blocker)

    report = send_activity_announcement(
        session, sender, activity, faculty=faculty, year_level=year_level
    )
    return _to_result(report)
