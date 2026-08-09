"""งานตั้งเวลา: เช็กนิสิตกลุ่มเสี่ยงแล้วส่งอีเมลอัตโนมัติวันละครั้ง (ข้อ 6.4)

``apscheduler`` ถูก import แบบ lazy เหมือน ``minio``/``easyocr``/``google-generativeai``
เทสต์และการรันในเครื่องที่ยังไม่ได้ติดตั้งจึงไม่พัง ตราบใดที่ยังไม่เปิดใช้งาน

ปิดไว้เป็นค่าเริ่มต้น (``NOTIFY_SCHEDULER_ENABLED=false``) ด้วยเหตุผลสองข้อ:
เครื่อง dev ไม่ควรมี thread ตั้งเวลาโผล่มาเอง และงานนี้ส่งอีเมลถึงนิสิตจริง
ควรเป็นการตัดสินใจเปิดของผู้ดูแล ไม่ใช่ผลข้างเคียงของการอัปเดตโค้ด

**ข้อควรรู้ตอน deploy:** scheduler อยู่ในโปรเซสของ uvicorn ถ้ารันหลาย worker
งานรายวันจะถูกยิงซ้ำตามจำนวน worker — เปิดใช้เมื่อรัน worker เดียว หรือย้ายไป
เป็น cron ภายนอกที่เรียก ``POST /notifications/at-risk`` แทน
"""

from __future__ import annotations

import logging
from typing import Optional

from sqlmodel import Session

from app.config import settings
from app.database import engine
from app.email import get_email_sender
from app.notifications import send_at_risk_notifications

logger = logging.getLogger(__name__)

_scheduler = None  # BackgroundScheduler เมื่อเปิดใช้งานแล้ว


def run_at_risk_job() -> None:
    """รอบรายวัน — เปิด session ของตัวเอง (คนละ thread กับ request)

    กลืน exception ทั้งหมดโดยตั้งใจ: งานตั้งเวลาที่โยน exception ออกไปจะถูก
    APScheduler ปิดทิ้งเงียบ ๆ แล้ววันถัดไปก็ไม่มีอีเมลออกโดยไม่มีใครรู้
    """
    try:
        with Session(engine) as session:
            report = send_at_risk_notifications(session, get_email_sender())
        logger.info(
            "งานแจ้งเตือนกลุ่มเสี่ยงรายวัน: ส่งสำเร็จ %s ฉบับ ล้มเหลว %s ฉบับ",
            report.sent,
            report.failed,
        )
    except Exception:  # noqa: BLE001 — งานเบื้องหลัง ห้ามล้มเงียบ ๆ
        logger.exception("งานแจ้งเตือนกลุ่มเสี่ยงรายวันล้มเหลว")


def start_notification_scheduler() -> Optional[object]:
    """เริ่ม scheduler ถ้าเปิดใช้งานไว้ — คืน None เมื่อปิดอยู่หรือ import ไม่ได้"""
    global _scheduler
    if not settings.notify_scheduler_enabled:
        logger.info("ปิดงานตั้งเวลาแจ้งเตือนอยู่ (NOTIFY_SCHEDULER_ENABLED=false)")
        return None
    if _scheduler is not None:
        return _scheduler

    from apscheduler.schedulers.background import BackgroundScheduler  # lazy

    scheduler = BackgroundScheduler(timezone="Asia/Bangkok")
    scheduler.add_job(
        run_at_risk_job,
        trigger="cron",
        hour=settings.notify_at_risk_hour,
        minute=0,
        id="at_risk_daily",
        # ถ้าเครื่องหลับ/รีสตาร์ตจนพลาดรอบ ให้ข้ามไปรอบถัดไป ดีกว่ายิงอีเมลย้อนหลัง
        # พร้อมกันหลายรอบตอนเปิดเครื่องมา
        misfire_grace_time=3600,
        coalesce=True,
        replace_existing=True,
    )
    scheduler.start()
    _scheduler = scheduler
    logger.info("เริ่มงานตั้งเวลาแจ้งเตือนกลุ่มเสี่ยง ทุกวันเวลา %s:00 น.", settings.notify_at_risk_hour)
    return scheduler


def shutdown_notification_scheduler() -> None:
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
