"""กฎของการเช็กอินหน้างานด้วย QR (ขอบเขต 6.4).

หลักการที่ตัดสินใจแล้ว (ดู PHASE_OnSite_QR_Checkin.md):
- สแกน QR = บันทึก `check_in_time` เท่านั้น **ไม่ให้ชั่วโมง** — ชั่วโมงยังต้อง
  ส่งหลักฐาน + เจ้าหน้าที่อนุมัติตามกฎ A3 เดิมทุกอย่าง
- ไม่ทำ QR หมุน (D1) เพราะเช็กอินไม่ให้ชั่วโมง แรงจูงใจโกงต่ำ — กันด้วยการ
  จำกัดช่วงเวลาเช็กอินอย่างเดียวก็พอ ลิงก์ที่ถ่ายรูปส่งต่อจึงยอมรับได้

ต่อยอดด้วย PHASE_F4_DeepLink_Checkin.md: QR เก็บ **URL เต็ม** แล้ว เพื่อให้กล้อง
มือถือปกติเปิดลิงก์เข้าเว็บเช็กอินได้เลย โดย `normalize_token` ยังรับรูปแบบเดิม
(prefix / token เปล่า) ต่อไป

โมดูลนี้เก็บส่วนที่ทั้ง router ของ activity (ออก QR) และ participation (รับสแกน)
ต้องเห็นตรงกัน เพื่อไม่ให้หน้าต่างเวลาที่แสดงบน QR ต่างจากที่ backend บังคับจริง
"""

from datetime import datetime, timedelta
from urllib.parse import parse_qs, urlsplit

from app.config import settings
from app.models import Activity

# รูปแบบเดิม (ก่อน F4): ข้อความ token ที่มี prefix ไว้ให้แอปแยกว่าเป็น QR ของระบบนี้
# ยังรับอยู่เพื่อความเข้ากันได้ย้อนหลังกับ QR ที่พิมพ์แจกไปแล้ว
QR_PREFIX = "TSU-CHECKIN:"

# ชื่อพารามิเตอร์ที่พา token ไปกับ URL — สั้นเพื่อให้ QR มีจุดน้อย สแกนติดง่าย
CHECKIN_QUERY_KEY = "c"

# path ของหน้าเช็กอินบนเว็บนิสิต — ขึ้นต้นด้วย `#` เพราะ Flutter web ใช้ hash
# routing เป็นค่าเริ่มต้น และ main.dart ไม่ได้เรียก usePathUrlStrategy()
CHECKIN_PATH = "/#/checkin"


def qr_payload(activity: Activity) -> str:
    """URL ที่เอาไปสร้างภาพ QR แสดงหน้างาน

    เก็บ **URL เต็ม** ไม่ใช่ token เปล่า เพื่อให้กล้องมือถือปกติ (iOS/Android)
    ขึ้นปุ่ม "เปิดลิงก์" ให้ — นิสิตจึงไม่ต้องเปิดแอปแล้วเข้าหน้าสแกนก่อน
    """
    base = settings.public_app_base_url.strip().rstrip("/")
    # ตั้งค่าเป็นชื่อโดเมนเปล่า ๆ (ไม่มี scheme) เป็นความพลาดที่มองไม่ออก: QR ยัง
    # สร้างได้ปกติ แต่กล้องมือถือจะไม่ขึ้นปุ่ม "เปิดลิงก์" ให้ — เติม https ให้เลย
    if "://" not in base:
        base = f"https://{base}"
    return f"{base}{CHECKIN_PATH}?{CHECKIN_QUERY_KEY}={activity.checkin_token}"


def _token_from_url(value: str) -> str:
    """ดึงค่า `c=` ออกจาก URL — คืนสตริงว่างถ้าไม่มี (จะถูกปฏิเสธเป็น QR ไม่ถูกต้อง)

    ต้องดูทั้ง query และ fragment เพราะ hash routing ทำให้ `?c=` ไปอยู่หลัง `#`
    (`https://host/#/checkin?c=xxx` → fragment คือ `/checkin?c=xxx` ทั้งก้อน)
    """
    parts = urlsplit(value)
    for section in (parts.query, parts.fragment):
        if not section:
            continue
        query = section.split("?", 1)[1] if "?" in section else section
        found = parse_qs(query).get(CHECKIN_QUERY_KEY)
        if found and found[0].strip():
            return found[0].strip()
    return ""


def normalize_token(raw: str) -> str:
    """ดึง token ออกจากสิ่งที่สแกนได้ หรือที่นิสิตพิมพ์มือ — รองรับ 3 รูปแบบ

    1. URL เต็มจาก QR แบบใหม่ (`https://.../#/checkin?c=<token>`)
    2. `TSU-CHECKIN:<token>` — QR แบบเดิมที่อาจพิมพ์แจกไปแล้ว
    3. token เปล่า — ช่องกรอกรหัสมือตอนกล้องใช้ไม่ได้
    """
    value = (raw or "").strip()
    if not value:
        return ""
    if value.upper().startswith(QR_PREFIX):
        return value[len(QR_PREFIX):].strip()
    # token จริงเป็น uuid hex ล้วน ไม่มีอักขระพวกนี้ — ถ้ามีแปลว่าเป็น URL
    # (หรือขยะ) ต้องดึง c= ให้ได้ ไม่งั้นถือว่าไม่ถูกต้อง
    if any(char in value for char in "/?#:"):
        return _token_from_url(value)
    return value


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
