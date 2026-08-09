"""endpoint สั่งส่งอีเมลแจ้งเตือน (ข้อ 6.4) — admin เท่านั้น

ทั้งสอง endpoint เป็นการ "สั่งส่งเดี๋ยวนี้" ด้วยมือ ส่วนรอบอัตโนมัติรายวันอยู่ที่
``app/scheduler.py`` ซึ่งเรียกฟังก์ชันชุดเดียวกันใน ``app/notifications.py``
เนื้อความและเกณฑ์ผู้รับจึงตรงกันเสมอ ไม่ว่าจะส่งด้วยมือหรือให้ระบบส่งเอง
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlmodel import Session, select

from app.auth import require_admin
from app.database import get_session
from app.email import EmailSender, get_email_sender
from app.models import Activity, Participation
from app.notifications import (
    NotificationReport,
    announcement_blocker,
    send_activity_announcement,
    send_at_risk_notifications,
)

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
    # ตัดรายชื่อไว้ไม่ให้ตอบกลับยาวเป็นพัน (นิสิต 100+ คน) แต่ยังพอให้ยืนยันได้ว่า
    # ส่งถูกกลุ่ม — จำนวนจริงอยู่ที่ sent/failed
    recipients: list[str]
    failed_recipients: list[str]


MAX_LISTED_RECIPIENTS = 50


def _to_result(report: NotificationReport) -> NotificationResult:
    return NotificationResult(
        subject=report.subject,
        sent=report.sent,
        failed=report.failed,
        recipients=report.recipients[:MAX_LISTED_RECIPIENTS],
        failed_recipients=report.failed_recipients[:MAX_LISTED_RECIPIENTS],
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
