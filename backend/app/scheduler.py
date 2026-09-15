"""งานตั้งเวลารายวัน: อีเมลนิสิตกลุ่มเสี่ยง + อีเมลเตือนกิจกรรมของพรุ่งนี้ (ข้อ 6.4)

``apscheduler`` ถูก import แบบ lazy เหมือน ``minio``/``easyocr``/``google-generativeai``
เทสต์และการรันในเครื่องที่ยังไม่ได้ติดตั้งจึงไม่พัง ตราบใดที่ยังไม่เปิดใช้งาน

ปิดไว้เป็นค่าเริ่มต้น (``NOTIFY_SCHEDULER_ENABLED=false``) ด้วยเหตุผลสองข้อ:
เครื่อง dev ไม่ควรมี thread ตั้งเวลาโผล่มาเอง และงานนี้ส่งอีเมลถึงนิสิตจริง
ควรเป็นการตัดสินใจเปิดของผู้ดูแล ไม่ใช่ผลข้างเคียงของการอัปเดตโค้ด

เปิด scheduler แล้ว แต่ละงานยังมีสวิตช์ของตัวเอง — ``NOTIFY_REMINDER_ENABLED`` (ค่าเริ่ม true)
และ ``NOTIFY_AT_RISK_ENABLED`` (ค่าเริ่ม false) เปิดเพื่อเตือนกิจกรรมจึงไม่พาอีเมลกลุ่มเสี่ยงออกไปด้วย

**ข้อควรรู้ตอน deploy:** scheduler อยู่ในโปรเซสของ uvicorn ถ้ารันหลาย worker
งานรายวันจะถูกยิงซ้ำตามจำนวน worker — เปิดใช้เมื่อรัน worker เดียว หรือย้ายไป
เป็น cron ภายนอกที่เรียก ``POST /notifications/at-risk`` และ
``POST /notifications/activity-reminders`` แทน
"""

from __future__ import annotations

import logging
from typing import Optional

from sqlmodel import Session

from app.config import settings
from app.database import engine
from app.email import get_email_sender
from app.notifications import send_activity_reminders, send_at_risk_notifications

logger = logging.getLogger(__name__)

_scheduler = None  # BackgroundScheduler เมื่อเปิดใช้งานแล้ว

AT_RISK_JOB_ID = "at_risk_daily"
REMINDER_JOB_ID = "activity_reminder_daily"


def run_at_risk_job() -> None:
    """รอบรายวัน — เปิด session ของตัวเอง (คนละ thread กับ request)

    กลืน exception ทั้งหมดโดยตั้งใจ: งานตั้งเวลาที่โยน exception ออกไปจะถูก
    APScheduler ปิดทิ้งเงียบ ๆ แล้ววันถัดไปก็ไม่มีอีเมลออกโดยไม่มีใครรู้
    """
    try:
        with Session(engine) as session:
            report = send_at_risk_notifications(session, get_email_sender())
        logger.info(
            "งานแจ้งเตือนกลุ่มเสี่ยงรายวัน: ส่งสำเร็จ %s ฉบับ ล้มเหลว %s ฉบับ "
            "ข้ามเพราะยังไม่ระบุอีเมล %s คน",
            report.sent,
            report.failed,
            report.skipped,
        )
    except Exception:  # noqa: BLE001 — งานเบื้องหลัง ห้ามล้มเงียบ ๆ
        logger.exception("งานแจ้งเตือนกลุ่มเสี่ยงรายวันล้มเหลว")


def run_activity_reminder_job() -> None:
    """รอบรายวัน — เตือนนิสิตที่สมัครกิจกรรมของ "พรุ่งนี้" ไว้

    กลืน exception ด้วยเหตุผลเดียวกับ :func:`run_at_risk_job`
    """
    try:
        with Session(engine) as session:
            report = send_activity_reminders(session, get_email_sender())
        logger.info(
            "งานเตือนกิจกรรมพรุ่งนี้: ส่งสำเร็จ %s ฉบับ ล้มเหลว %s ฉบับ "
            "ข้ามเพราะยังไม่ระบุอีเมล %s ราย",
            report.sent,
            report.failed,
            report.skipped,
        )
    except Exception:  # noqa: BLE001 — งานเบื้องหลัง ห้ามล้มเงียบ ๆ
        logger.exception("งานเตือนกิจกรรมพรุ่งนี้ล้มเหลว")


def start_notification_scheduler() -> Optional[object]:
    """เริ่ม scheduler ถ้าเปิดใช้งานไว้ — คืน None เมื่อปิดอยู่ ไม่มีงานที่เปิด หรือ import ไม่ได้"""
    global _scheduler
    if not settings.notify_scheduler_enabled:
        logger.info("ปิดงานตั้งเวลาแจ้งเตือนอยู่ (NOTIFY_SCHEDULER_ENABLED=false)")
        return None
    if not (settings.notify_at_risk_enabled or settings.notify_reminder_enabled):
        # ไม่มีงานให้รัน ไม่ต้องมี thread ค้างไว้เปล่า ๆ
        logger.warning(
            "เปิด NOTIFY_SCHEDULER_ENABLED แต่ปิดทุกงาน (NOTIFY_REMINDER_ENABLED / NOTIFY_AT_RISK_ENABLED) "
            "— ไม่เริ่ม scheduler"
        )
        return None
    if _scheduler is not None:
        return _scheduler

    from apscheduler.schedulers.background import BackgroundScheduler  # lazy

    scheduler = BackgroundScheduler(timezone="Asia/Bangkok")
    if settings.notify_at_risk_enabled:
        scheduler.add_job(
            run_at_risk_job,
            trigger="cron",
            hour=settings.notify_at_risk_hour,
            minute=0,
            id=AT_RISK_JOB_ID,
            # ถ้าเครื่องหลับ/รีสตาร์ตจนพลาดรอบ ให้ข้ามไปรอบถัดไป ดีกว่ายิงอีเมลย้อนหลัง
            # พร้อมกันหลายรอบตอนเปิดเครื่องมา
            misfire_grace_time=3600,
            coalesce=True,
            replace_existing=True,
        )
    if settings.notify_reminder_enabled:
        scheduler.add_job(
            run_activity_reminder_job,
            trigger="cron",
            hour=settings.notify_activity_reminder_hour,
            minute=0,
            id=REMINDER_JOB_ID,
            # พลาดรอบแล้วข้ามไปเลย — ยิงย้อนหลังตอนเปิดเครื่องมาอาจเป็นคนละวันกับที่
            # ตั้งใจ แล้วนิสิตจะได้อีเมลว่า "พรุ่งนี้มีกิจกรรม" ทั้งที่งานจบไปแล้ว
            misfire_grace_time=3600,
            coalesce=True,
            replace_existing=True,
        )
    scheduler.start()
    _scheduler = scheduler
    # WARNING ไม่ใช่ INFO: logger ของแอปไม่ขึ้นใน log ของ uvicorn ที่ระดับ INFO — การเปิดส่งอีเมลจริง
    # ต้องมองเห็นได้จาก docker compose logs
    logger.warning(
        "เริ่มงานตั้งเวลารายวัน (ส่งอีเมลจริง): กลุ่มเสี่ยง %s · เตือนกิจกรรมพรุ่งนี้ %s",
        f"{settings.notify_at_risk_hour}:00 น." if settings.notify_at_risk_enabled else "ปิด",
        f"{settings.notify_activity_reminder_hour}:00 น." if settings.notify_reminder_enabled else "ปิด",
    )
    return scheduler


def shutdown_notification_scheduler() -> None:
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
