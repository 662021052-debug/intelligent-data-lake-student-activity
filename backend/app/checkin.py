"""กฎของการเช็กอินหน้างานด้วย QR (ขอบเขต 6.4).

หลักการที่ตัดสินใจแล้ว (ดู PHASE_OnSite_QR_Checkin.md):
- สแกน QR = บันทึก `check_in_time` เท่านั้น **ไม่ให้ชั่วโมง** — ชั่วโมงยังต้อง
  ส่งหลักฐาน + เจ้าหน้าที่อนุมัติตามกฎ A3 เดิมทุกอย่าง
- ไม่ทำ QR หมุน (D1) เพราะเช็กอินไม่ให้ชั่วโมง แรงจูงใจโกงต่ำ — กันด้วยการ
  จำกัดช่วงเวลาเช็กอินอย่างเดียวก็พอ

โมดูลนี้เก็บส่วนที่ทั้ง router ของ activity (ออก QR) และ participation (รับสแกน)
ต้องเห็นตรงกัน เพื่อไม่ให้หน้าต่างเวลาที่แสดงบน QR ต่างจากที่ backend บังคับจริง
"""

from datetime import datetime, timedelta

from app.config import settings
from app.models import Activity

# นำหน้า payload ใน QR เพื่อให้แอปแยกออกว่า QR ที่สแกนเจอเป็นของระบบนี้
# (backend รับทั้งแบบมีและไม่มี prefix เผื่อ QR ที่ออกไปแล้ว/กรอกรหัสมือ)
QR_PREFIX = "TSU-CHECKIN:"


def qr_payload(activity: Activity) -> str:
    """ข้อความที่ frontend เอาไปสร้างภาพ QR แสดงหน้างาน."""
    return f"{QR_PREFIX}{activity.checkin_token}"


def normalize_token(raw: str) -> str:
    """ดึง token ออกจากสิ่งที่สแกนได้ (หรือที่นิสิตพิมพ์มือ)."""
    token = (raw or "").strip()
    if token.upper().startswith(QR_PREFIX):
        token = token[len(QR_PREFIX):].strip()
    return token


def checkin_window(activity: Activity) -> tuple[datetime, datetime]:
    """ช่วงเวลาที่เช็กอินได้ของกิจกรรมนี้ (UTC, สอดคล้องกับ start_at ในฐานข้อมูล).

    activity ไม่มี `end_at` ในสคีมา จึงประมาณเวลาจบจาก `activity.hours`
    (จำนวนชั่วโมงที่กิจกรรมให้ = ความยาวกิจกรรม) แล้วบวกเวลาผ่อนผันท้ายงาน
    """
    opens_at = activity.start_at - timedelta(minutes=settings.checkin_open_before_minutes)
    duration = timedelta(hours=max(activity.hours or 0, 0))
    closes_at = (
        activity.start_at + duration + timedelta(minutes=settings.checkin_close_after_minutes)
    )
    return opens_at, closes_at
