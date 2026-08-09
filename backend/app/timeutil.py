"""เวลาแบบไทยที่หลายโมดูลต้องเห็นตรงกัน

`start_at` ของกิจกรรมเป็น "เวลาไทยแบบไม่มีโซน" (ฟอร์มฝั่งเว็บประกอบจากนาฬิกา
เครื่องผู้ใช้แล้วส่งมาดิบ ๆ) ต่างจาก timestamp ที่ระบบเขียนเองด้วย `utcnow()`
การเทียบ/แสดงผลจึงต้องอิงเวลาไทยเสมอ ไม่งั้นวันจะเพี้ยนไปหนึ่งวันในช่วงหัวค่ำ
"""

from datetime import date, datetime, timedelta, timezone

TZ_TH = timezone(timedelta(hours=7))

THAI_MONTHS_SHORT = [
    "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
    "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค.",
]


def now_th() -> datetime:
    """เวลาปัจจุบันตามโซนไทย (มี tzinfo)"""
    return datetime.now(TZ_TH)


def now_th_naive() -> datetime:
    """เวลาปัจจุบันตามโซนไทยแบบไม่มีโซน — ใช้เทียบกับ `start_at` ที่เก็บในฐานข้อมูล"""
    return now_th().replace(tzinfo=None)


def today_th() -> date:
    return now_th().date()


def format_thai_datetime(value: datetime) -> str:
    """`2026-08-10T09:00` → `10 ส.ค. 2569 เวลา 09:00 น.` (ปี พ.ศ. เต็ม)

    ใช้ในอีเมลที่ส่งถึงนิสิต จึงเขียนเป็นรูปแบบที่คนอ่าน ไม่ใช่ ISO
    """
    return (
        f"{value.day} {THAI_MONTHS_SHORT[value.month - 1]} {value.year + 543} "
        f"เวลา {value.hour:02d}:{value.minute:02d} น."
    )
