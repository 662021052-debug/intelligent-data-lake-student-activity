"""สคริปต์ใส่ข้อมูลสมมุติสำหรับเดโม: นิสิต ~100 คน (ชั้นปี 1–4), กิจกรรม ~28 รายการ,
การเข้าร่วมกว่า 1,000 แถว พร้อมกระจายชั่วโมงสะสมให้เห็นทุกกลุ่มในแดชบอร์ด

รัน: python seed.py
     python seed.py --refresh-live   # เลื่อนกิจกรรมเดโมเช็กอิน QR ให้กำลังจัดตอนนี้อีกครั้ง

หลักการที่ยึด (ห้ามแก้):
- ชั่วโมงมาจาก ``activity.hours`` เท่านั้น ไม่ hardcode ต่อแถว (กฎ A2)
- นับเข้าชั่วโมงสะสมเฉพาะ ``evidence_status = approved`` เท่านั้น
- ทุกแถวที่ approved/rejected ต้องมีหลักฐาน Bronze จริง (กฎ A3)
"""
import hashlib
import random
import sys
import uuid
from collections import defaultdict
from datetime import datetime, timedelta

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlmodel import Session, select

from app.auth import hash_password
from app.config import settings
from app.database import create_db_and_tables, engine
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    RawFile,
    Student,
    StudentStatus,
    User,
    UserRole,
)
from app.storage import get_storage
from app.timeutil import now_th_naive
from seed_evidence import (
    VARIANT_FULL,
    VARIANT_LOW_QUALITY,
    VARIANT_NO_NAME,
    find_thai_font,
    pick_variant,
    render_certificate,
)

# ตั้ง seed ให้ข้อมูลเดโมออกมาเหมือนเดิมทุกครั้ง (ตัวเลขในเล่ม/สไลด์จะได้ตรงกัน)
RANDOM_SEED = 20260726

FACULTIES = {
    "วิศวกรรมศาสตร์": ["วิศวกรรมคอมพิวเตอร์", "วิศวกรรมไฟฟ้า", "วิศวกรรมโยธา"],
    "วิทยาศาสตร์": ["วิทยาการคอมพิวเตอร์", "เคมี", "ชีววิทยา"],
    "ศิลปศาสตร์": ["ภาษาอังกฤษ", "ภาษาไทย"],
    "บริหารธุรกิจ": ["การตลาด", "การเงิน", "การจัดการ"],
    "ศึกษาศาสตร์": ["คณิตศาสตร์ศึกษา", "การศึกษาปฐมวัย"],
    "พยาบาลศาสตร์": ["พยาบาลศาสตร์"],
    "นิติศาสตร์": ["นิติศาสตร์"],
}

# รหัสสาขา 4 หลัก (เลียนแบบรหัสนิสิต ม.ทักษิณ) ประกอบเป็นรหัสนิสิต 9 หลัก:
# {ปีเข้าศึกษา 2 หลัก}{รหัสสาขา 4 หลัก}{ลำดับ 3 หลัก} เช่น 662021052
MAJOR_PROGRAM_CODE = {
    "วิศวกรรมคอมพิวเตอร์": "2021",
    "วิศวกรรมไฟฟ้า": "2022",
    "วิศวกรรมโยธา": "2023",
    "วิทยาการคอมพิวเตอร์": "0311",
    "เคมี": "0312",
    "ชีววิทยา": "0313",
    "ภาษาอังกฤษ": "0421",
    "ภาษาไทย": "0422",
    "การตลาด": "0531",
    "การเงิน": "0532",
    "การจัดการ": "0533",
    "คณิตศาสตร์ศึกษา": "0611",
    "การศึกษาปฐมวัย": "0612",
    "พยาบาลศาสตร์": "0711",
    "นิติศาสตร์": "0811",
}

# ชั้นปี → ปีที่เข้าศึกษา (2 หลักหน้าของรหัสนิสิต): ปี 1 = รหัส 68, ปี 4 = รหัส 65
ENTRY_YEAR_BY_LEVEL = {1: 68, 2: 67, 3: 66, 4: 65}

STUDENTS_PER_YEAR = 25  # รวม 4 ชั้นปี = 100 คน


def make_student_code(major: str, year_level: int, seq: int) -> str:
    """รหัสนิสิต 9 หลัก: ปีเข้าศึกษา + รหัสสาขา + ลำดับ (เช่น 662021052)."""
    return f"{ENTRY_YEAR_BY_LEVEL[year_level]}{MAJOR_PROGRAM_CODE[major]}{seq:03d}"


FIRST_NAMES = [
    "สมชาย", "สมหญิง", "วิชัย", "วิภา", "ประยุทธ", "นิภา", "อนุชา", "ศิริพร",
    "ธนกร", "กัญญา", "ชัยวัฒน์", "พรทิพย์", "ธีรพงษ์", "อรุณี", "สุรชัย", "มาลี",
    "ปิยะ", "รัตนา", "เอกชัย", "จันทร์เพ็ญ", "ณัฐวุฒิ", "ปณิดา", "กิตติศักดิ์",
    "ชนิสรา", "ภาณุพงศ์", "ธัญชนก", "อภิสิทธิ์", "วรรณิศา", "จิรายุ", "เบญจวรรณ",
    "สหรัฐ", "ปาริชาต", "ยุทธนา", "สุพรรษา", "ณรงค์ฤทธิ์", "อรปรียา", "พีรพัฒน์",
    "ชลธิชา", "ศุภกร", "นันท์นภัส", "ทัศนัย", "กมลชนก", "วชิรวิทย์", "ธิดารัตน์",
    "อดิศักดิ์", "ศศิธร", "ภูมินทร์", "จุฑามาศ", "รัชชานนท์", "สิริกร",
]
LAST_NAMES = [
    "ใจดี", "รักเรียน", "สุขสันต์", "ทองคำ", "แสงจันทร์", "ศรีสุข", "บุญมี",
    "พงษ์ไพร", "วงศ์ษา", "ชูเกียรติ", "แก้วมณี", "นวลจันทร์", "พรหมทอง",
    "สุวรรณรัตน์", "เพชรรัตน์", "จันทร์แก้ว", "หนูเอียด", "ขวัญเมือง", "ทิพย์มณี",
    "สังข์ทอง", "บัวแก้ว", "ยอดแก้ว", "คงเจริญ", "มณีโชติ", "อินทรสุวรรณ",
    "ปานทอง", "ชูศรี", "ดำริห์", "เรืองฤทธิ์", "สมบูรณ์",
]

LOCATIONS = [
    "หอประชุมใหญ่", "ห้อง SC101", "สนามกีฬากลาง", "ลานกิจกรรม", "ห้องประชุมคณะ",
    "ศูนย์ประชุมนานาชาติ", "อาคารเรียนรวม 1", "โรงยิมเนเซียม", "ชุมชนบ้านปากพะยูน",
]

# เกณฑ์ชั่วโมงกิจกรรม ม.ทักษิณ (โครงสร้าง พ.ศ. 2560–2566, หลักสูตร 4 ปี, รวม 60 ชม. ขั้นต่ำ)
HOUR_STRUCTURE = [
    ("พัฒนาทักษะชีวิต", 12, [
        ("กิจกรรมเสริมสร้างคุณค่าแห่งตน", 8),
        ("กิจกรรมบูรณาการ 1", 4),
    ]),
    ("TSU รับใช้สังคม", 12, [
        ("กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 12),
    ]),
    ("ศิลปวัฒนธรรมอาเซียน", 8, [
        ("กิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน", 6),
        ("กิจกรรมบูรณาการ 3", 2),
    ]),
    ("พัฒนาคุณธรรมและวินัย", 8, [
        ("กิจกรรมสร้างวินัยในตนเอง", 4),
        ("กิจกรรมบูรณาการ 4", 4),
    ]),
    ("ใฝ่เรียนรู้ตลอดชีวิต", 20, [
        ("กิจกรรม ICT กับการรู้สารสนเทศ 1", 2),
        ("กิจกรรม ICT กับการรู้สารสนเทศ 2", 2),
        ("กิจกรรมเรียนรู้และรู้เท่าทันเทคโนโลยีดิจิทัล", 4),
        ("กิจกรรมเตรียมความพร้อมก่อนการใช้ชีวิตในมหาวิทยาลัย (ปฐมนิเทศ)", 4),
        ("กิจกรรมเตรียมความก่อนการใช้ชีวิตนอกมหาวิทยาลัย (ปัจฉิมนิเทศ)", 4),
        ("กิจกรรมบูรณาการ 5", 4),
    ]),
]

# กิจกรรมสมมุติ: ชื่อ / ประเภท / กิจกรรมย่อย(หมวดชั่วโมง) / ชั่วโมง / ความจุ
# กระจายครบทั้ง 5 หมวด เพื่อให้นิสิตสะสมชั่วโมงได้หลายหมวด ไม่กองอยู่หมวดเดียว
# (name, activity_type, subcategory_name, hours, max_participants)
ACTIVITY_DEFS = [
    # --- หมวด 1 พัฒนาทักษะชีวิต ---
    ("กีฬาสีมหาวิทยาลัย", "กีฬา", "กิจกรรมเสริมสร้างคุณค่าแห่งตน", 4, 150),
    ("อบรมพัฒนาบุคลิกภาพและการสื่อสาร", "อบรม/สัมมนา", "กิจกรรมเสริมสร้างคุณค่าแห่งตน", 4, 80),
    ("ค่ายผู้นำนิสิตรุ่นใหม่", "อบรม/สัมมนา", "กิจกรรมเสริมสร้างคุณค่าแห่งตน", 6, 40),
    ("เดิน-วิ่งการกุศล TSU Run", "กีฬา", "กิจกรรมบูรณาการ 1", 4, 150),
    ("เวิร์กช็อปสุขภาพจิตดีมีสุข", "อบรม/สัมมนา", "กิจกรรมบูรณาการ 1", 2, 60),
    # --- หมวด 2 TSU รับใช้สังคม ---
    ("ค่ายอาสาพัฒนาชนบท", "จิตอาสา",
     "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 6, 60),
    ("จิตอาสาบริจาคโลหิต", "จิตอาสา",
     "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 3, 110),
    ("โครงการ Big Cleaning Day ชุมชนสะอาด", "จิตอาสา",
     "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 4, 120),
    ("อาสาสอนน้องโรงเรียนตำรวจตระเวนชายแดน", "จิตอาสา",
     "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 6, 35),
    ("ปลูกป่าชายเลนอนุรักษ์ทะเลสาบสงขลา", "จิตอาสา",
     "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 4, 100),
    # --- หมวด 3 ศิลปวัฒนธรรมอาเซียน ---
    ("เทศกาลศิลปวัฒนธรรมอาเซียน", "ศิลปวัฒนธรรม", "กิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน", 6, 120),
    ("สืบสานประเพณีลอยกระทง", "ศิลปวัฒนธรรม", "กิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน", 3, 120),
    ("อบรมนาฏศิลป์และดนตรีไทย", "ศิลปวัฒนธรรม", "กิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน", 4, 70),
    ("ค่ายแลกเปลี่ยนวัฒนธรรมนิสิตอาเซียน", "ศิลปวัฒนธรรม", "กิจกรรมบูรณาการ 3", 2, 75),
    # --- หมวด 4 พัฒนาคุณธรรมและวินัย ---
    ("อบรมคุณธรรมจริยธรรมนิสิตใหม่", "อบรม/สัมมนา", "กิจกรรมสร้างวินัยในตนเอง", 4, 120),
    ("ปฏิบัติธรรมเนื่องในวันมาฆบูชา", "ศาสนา", "กิจกรรมสร้างวินัยในตนเอง", 3, 90),
    ("ค่ายอนุรักษ์สิ่งแวดล้อม", "จิตอาสา", "กิจกรรมบูรณาการ 4", 4, 70),
    ("โครงการวินัยจราจรในมหาวิทยาลัย", "อบรม/สัมมนา", "กิจกรรมบูรณาการ 4", 2, 110),
    # --- หมวด 5 ใฝ่เรียนรู้ตลอดชีวิต ---
    ("ปฐมนิเทศนิสิตใหม่", "อบรม/สัมมนา",
     "กิจกรรมเตรียมความพร้อมก่อนการใช้ชีวิตในมหาวิทยาลัย (ปฐมนิเทศ)", 4, 120),
    ("สัมมนาเตรียมความพร้อมสู่การทำงาน", "อบรม/สัมมนา",
     "กิจกรรมเตรียมความก่อนการใช้ชีวิตนอกมหาวิทยาลัย (ปัจฉิมนิเทศ)", 4, 110),
    ("สัมมนาเขียน Resume และเทคนิคสัมภาษณ์งาน", "อบรม/สัมมนา",
     "กิจกรรมเตรียมความก่อนการใช้ชีวิตนอกมหาวิทยาลัย (ปัจฉิมนิเทศ)", 4, 80),
    ("อบรมทักษะดิจิทัลสำหรับนิสิต", "อบรม/สัมมนา", "กิจกรรมเรียนรู้และรู้เท่าทันเทคโนโลยีดิจิทัล", 4, 120),
    ("อบรมรู้เท่าทันภัยไซเบอร์", "อบรม/สัมมนา", "กิจกรรมเรียนรู้และรู้เท่าทันเทคโนโลยีดิจิทัล", 2, 100),
    ("งานสัปดาห์วิทยาศาสตร์แห่งชาติ", "วิชาการ", "กิจกรรม ICT กับการรู้สารสนเทศ 1", 2, 150),
    ("อบรมการสืบค้นสารสนเทศห้องสมุด", "วิชาการ", "กิจกรรม ICT กับการรู้สารสนเทศ 1", 2, 60),
    ("แข่งขันตอบปัญหาวิชาการ", "วิชาการ", "กิจกรรม ICT กับการรู้สารสนเทศ 2", 2, 40),
    ("TSU Startup Camp", "วิชาการ", "กิจกรรมบูรณาการ 5", 6, 30),
    ("อบรม AI และการใช้งานอย่างรู้เท่าทัน", "วิชาการ", "กิจกรรมบูรณาการ 5", 4, 90),
]

# กิจกรรมที่ยัง "รออนุมัติ" (staff สร้างไว้ ยังไม่ผ่าน admin) — ยังไม่มีคนลงทะเบียน
PENDING_ACTIVITY_NAMES = {
    "ค่ายผู้นำนิสิตรุ่นใหม่",
    "อบรมรู้เท่าทันภัยไซเบอร์",
    "อาสาสอนน้องโรงเรียนตำรวจตระเวนชายแดน",
}
# กิจกรรม "กำลังจัดอยู่ตอนนี้" — มีไว้เดโมการเช็กอินหน้างานด้วย QR โดยเฉพาะ
# กิจกรรมอื่นทั้งหมดอยู่ในอดีต จึงอยู่นอกช่วงเช็กอินและสแกนไม่ผ่านสักอัน
# เริ่มไปแล้ว 30 นาที ยาว 3 ชม. → อยู่กลางหน้าต่างเช็กอินพอดีตอนรัน seed
LIVE_ACTIVITY = {
    "name": "จิตอาสาพัฒนามหาวิทยาลัย (กำลังจัดอยู่ตอนนี้)",
    "activity_type": "จิตอาสา",
    "subcategory_name": "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม",
    "hours": 3,
    "max_participants": 200,
    "started_minutes_ago": 30,
}
# จำนวนนิสิตที่ "สมัครล่วงหน้า" ไว้กับกิจกรรม live — คนอื่นสแกนเข้ามาเป็น walk-up
LIVE_ACTIVITY_PREREGISTERED = 8

# กิจกรรมที่ตั้งใจให้ "เต็ม/ปิดรับสมัคร" เพื่อเดโมการแนะนำกิจกรรมทดแทน (Phase 18):
# ความจุจะถูกตั้งเท่ากับจำนวนผู้ลงทะเบียนจริงหลังสุ่มเสร็จ
FULL_ACTIVITY_NAMES = {"TSU Startup Camp", "แข่งขันตอบปัญหาวิชาการ"}

# กลุ่มชั่วโมงสะสมเป้าหมาย (เกณฑ์ผ่าน = 60 ชม., กลุ่มเสี่ยง = ต่ำกว่า 50% = ต่ำกว่า 30 ชม.)
PROFILE_TARGETS = {
    "passed": (60, 72),    # ผ่านเกณฑ์แล้ว
    "near": (45, 58),      # เกือบผ่าน (75–97%)
    "mid": (30, 44),       # ปานกลาง ยังไม่เสี่ยง
    "at_risk": (6, 28),    # กลุ่มเสี่ยง (<50%)
    "none": (0, 0),        # ยังไม่เริ่มเก็บชั่วโมง
}

# สัดส่วนกลุ่มตามชั้นปี: ปีสูงส่วนใหญ่ใกล้ครบ/ครบแล้ว ปี 1 เพิ่งเริ่ม
YEAR_PROFILE_WEIGHTS = {
    4: {"passed": 62, "near": 18, "mid": 8, "at_risk": 9, "none": 3},
    3: {"passed": 42, "near": 26, "mid": 14, "at_risk": 14, "none": 4},
    2: {"passed": 10, "near": 16, "mid": 34, "at_risk": 30, "none": 10},
    1: {"passed": 2, "near": 5, "mid": 8, "at_risk": 60, "none": 25},
}

# บังคับให้ทุกชั้นปีมีครบทั้ง 4 กลุ่มอย่างน้อยกลุ่มละ 1 คน เพื่อให้กราฟ/ตารางกลุ่มเสี่ยง
# มีข้อมูลจริงในทุกชั้นปี ที่เหลือค่อยสุ่มตามสัดส่วนด้านบน
GUARANTEED_PROFILES = ["passed", "near", "at_risk", "none"]

# นิสิตปีต้น ๆ ที่อยู่ในกลุ่มเสี่ยงควรมีชั่วโมง "น้อยจริง" ไม่ใช่เกือบ 30
AT_RISK_CEILING_BY_YEAR = {1: 14, 2: 22}


def target_hours(profile: str, year_level: int, rng: random.Random) -> int:
    low, high = PROFILE_TARGETS[profile]
    if profile == "at_risk":
        high = AT_RISK_CEILING_BY_YEAR.get(year_level, high)
    return rng.randint(low, high)


def _pick_activities_for_target(ordered_activities, target, allow_overshoot):
    """เลือกกิจกรรม (ที่สลับหมวดมาแล้ว) ให้ชั่วโมงรวมใกล้ ``target`` ที่สุดโดยไม่เกิน

    ``allow_overshoot`` ใช้กับกลุ่ม "ผ่านเกณฑ์" เท่านั้น เพื่อให้ยอดถึง 60 ชม. จริง
    """
    picked = []
    total = 0.0
    for activity in ordered_activities:
        if total >= target:
            break
        if total + activity.hours <= target:
            picked.append(activity)
            total += activity.hours

    if allow_overshoot and total < target:
        remaining = sorted(
            (a for a in ordered_activities if a not in picked), key=lambda a: a.hours
        )
        for activity in remaining:
            picked.append(activity)
            total += activity.hours
            if total >= target:
                break
    return picked, total


def _interleave_by_category(by_category, rng):
    """ไล่หยิบกิจกรรมสลับหมวดไปเรื่อย ๆ เพื่อให้ชั่วโมงกระจายหลายหมวด ไม่กองหมวดเดียว"""
    pools = {key: rng.sample(items, len(items)) for key, items in by_category.items()}
    keys = list(pools)
    rng.shuffle(keys)
    ordered = []
    while any(pools.values()):
        for key in keys:
            if pools[key]:
                ordered.append(pools[key].pop())
    return ordered


def _upsert_live_activity(
    session,
    *,
    location: str,
    subcategory_id: int,
    staff_user_id: int,
    admin_user_id: int,
) -> Activity:
    """สร้าง (หรือเลื่อนเวลา) กิจกรรมเดโมให้ "กำลังจัดอยู่ตอนนี้"

    หน้าต่างเช็กอินผูกกับ ``start_at`` กิจกรรมที่ seed ไว้เมื่อวานจึงหลุดช่วงไปแล้ว
    — ฟังก์ชันนี้ทำให้เรียกซ้ำเพื่อเดโมใหม่ได้โดยไม่ต้อง seed ทั้งฐานข้อมูล
    """
    # start_at เป็นเวลาไทยแบบไม่มีโซน (หน้าต่างเช็กอินเทียบกับเวลาไทย)
    started_at = now_th_naive() - timedelta(minutes=LIVE_ACTIVITY["started_minutes_ago"])
    activity = session.exec(
        select(Activity).where(Activity.name == LIVE_ACTIVITY["name"])
    ).first()

    if activity is None:
        activity = Activity(
            name=LIVE_ACTIVITY["name"],
            activity_type=LIVE_ACTIVITY["activity_type"],
            is_required=False,
            max_participants=LIVE_ACTIVITY["max_participants"],
            location=location,
            hours=LIVE_ACTIVITY["hours"],
            subcategory_id=subcategory_id,
            created_by=staff_user_id,  # staff เจ้าของ → เดโมปุ่ม "แสดง QR เช็กอิน" ได้
        )
    activity.start_at = started_at
    activity.approval_status = ApprovalStatus.approved
    activity.approved_by = admin_user_id
    activity.approved_at = datetime.utcnow()
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def refresh_live_activity() -> None:
    """เลื่อนกิจกรรมเดโมเช็กอินให้กลับมา "กำลังจัดอยู่ตอนนี้" แล้วล้างการเช็กอินเดิม

    ใช้ตอนอยากเดโมซ้ำในฐานข้อมูลที่ seed ไว้แล้ว (`python seed.py --refresh-live`)
    แตะเฉพาะกิจกรรมเดโมตัวนี้ตัวเดียว ไม่ยุ่งกับข้อมูลอื่น
    """
    with Session(engine) as session:
        staff_user = session.exec(select(User).where(User.role == UserRole.staff)).first()
        admin_user = session.exec(select(User).where(User.role == UserRole.admin)).first()
        subcategory = session.exec(
            select(HourSubcategory).where(
                HourSubcategory.name == LIVE_ACTIVITY["subcategory_name"]
            )
        ).first()
        if staff_user is None or admin_user is None or subcategory is None:
            print("ยังไม่มีข้อมูลพื้นฐานในฐานข้อมูล — รัน `python seed.py` ก่อน")
            return

        activity = _upsert_live_activity(
            session,
            location=LOCATIONS[0],
            subcategory_id=subcategory.id,
            staff_user_id=staff_user.id,
            admin_user_id=admin_user.id,
        )

        # ล้างเวลาเช็กอินของกิจกรรมนี้ เพื่อให้คนเดิมสแกนเดโมได้อีกรอบ
        already = session.exec(
            select(Participation).where(
                Participation.activity_id == activity.id,
                Participation.check_in_time.is_not(None),
            )
        ).all()
        for participation in already:
            participation.check_in_time = None
            session.add(participation)
        session.commit()

        print(
            f"กิจกรรมเดโมเช็กอิน QR: \"{activity.name}\" (id={activity.id}) "
            f"เริ่ม {activity.start_at:%Y-%m-%d %H:%M} (เวลาไทย) — ล้างการเช็กอินเดิม {len(already)} รายการ"
        )


def seed() -> None:
    create_db_and_tables()
    rng = random.Random(RANDOM_SEED)

    with Session(engine) as session:
        if session.exec(select(User)).first():
            print("มีข้อมูลอยู่แล้ว ข้ามการ seed")
            return

        # --- students: 25 คน/ชั้นปี = 100 คน, รหัส 9 หลักแบบ ม.ทักษิณ (68/67/66/65) ---
        name_pool = [f"{f} {l}" for f in FIRST_NAMES for l in LAST_NAMES]
        rng.shuffle(name_pool)
        major_pool = [(fac, major) for fac, majors in FACULTIES.items() for major in majors]

        students = []
        name_iter = iter(name_pool)
        for year_level in (4, 3, 2, 1):
            for seq in range(1, STUDENTS_PER_YEAR + 1):
                faculty, major = major_pool[(year_level * 7 + seq) % len(major_pool)]
                students.append(
                    Student(
                        student_id=make_student_code(major, year_level, seq),
                        full_name=next(name_iter),
                        faculty=faculty,
                        major=major,
                        year_level=year_level,
                        # นิสิตส่วนน้อยพ้นสภาพ/ลาพัก เพื่อให้ข้อมูลดูสมจริง
                        status=StudentStatus.inactive if rng.random() < 0.04 else StudentStatus.active,
                    )
                )
        session.add_all(students)
        session.commit()
        for obj in students:
            session.refresh(obj)

        # --- staff/admin logins ---
        admin_user = User(username="admin", hashed_password=hash_password("admin123"), role=UserRole.admin)
        staff_user = User(username="staff", hashed_password=hash_password("staff123"), role=UserRole.staff)
        # --- นิสิตล็อกอินด้วย "รหัสนิสิต" (ไม่มีบัญชีชื่อ "student" อีกต่อไป);
        #     รหัสผ่านเริ่มต้น = รหัสนิสิต เพื่อความสะดวกในการเดโม ---
        student_users = [
            User(
                username=s.student_id,
                hashed_password=hash_password(s.student_id),
                role=UserRole.student,
                student_id=s.id,
            )
            for s in students
        ]
        users = [admin_user, staff_user, *student_users]
        session.add_all(users)
        session.commit()
        for user in users:
            session.refresh(user)

        # --- hour categories/subcategories (เกณฑ์ชั่วโมงกิจกรรม) ---
        subcategory_id_by_name: dict[str, int] = {}
        category_id_by_subcategory_id: dict[int, int] = {}
        category_path_by_subcategory_id: dict[int, str] = {}
        total_required_hours = 0.0
        for category_name, category_hours, subs in HOUR_STRUCTURE:
            total_required_hours += category_hours
            category = HourCategory(name=category_name, required_hours=category_hours)
            session.add(category)
            session.commit()
            session.refresh(category)

            for sub_name, sub_hours in subs:
                subcategory = HourSubcategory(
                    category_id=category.id, name=sub_name, required_hours=sub_hours
                )
                session.add(subcategory)
                session.commit()
                session.refresh(subcategory)
                subcategory_id_by_name[sub_name] = subcategory.id
                category_id_by_subcategory_id[subcategory.id] = category.id
                # ชื่อหมวดเต็มไว้พิมพ์ลงใบประกาศ ("หมวดแม่ › หมวดย่อย")
                category_path_by_subcategory_id[subcategory.id] = f"{category_name} › {sub_name}"

        # --- activities: กระจายวันตลอดปีการศึกษา, สลับเจ้าของ staff/admin (F3),
        #     บางรายการยังรออนุมัติ ---
        activities = []
        base_date = datetime(2025, 8, 5)
        for i, (name, activity_type, sub_name, hours, capacity) in enumerate(ACTIVITY_DEFS):
            owner_is_admin = i % 2 == 1  # alternate owners
            owner_id = admin_user.id if owner_is_admin else staff_user.id
            is_pending = name in PENDING_ACTIVITY_NAMES
            activity = Activity(
                name=name,
                activity_type=activity_type,
                # กิจกรรมกลางของมหาวิทยาลัย (ปฐมนิเทศ/ปัจฉิมนิเทศ/คุณธรรม) = บังคับ
                is_required=sub_name.startswith("กิจกรรมเตรียมความ")
                or sub_name == "กิจกรรมสร้างวินัยในตนเอง",
                max_participants=capacity,
                start_at=base_date + timedelta(days=i * 14),
                location=rng.choice(LOCATIONS),
                hours=hours,
                subcategory_id=subcategory_id_by_name[sub_name],
                created_by=owner_id,
                approval_status=ApprovalStatus.pending if is_pending else ApprovalStatus.approved,
                approved_by=None if is_pending else admin_user.id,
                approved_at=None if is_pending else base_date,
            )
            activities.append(activity)
        session.add_all(activities)
        session.commit()
        for obj in activities:
            session.refresh(obj)

        approved_activities = [a for a in activities if a.approval_status == ApprovalStatus.approved]
        by_category = defaultdict(list)
        for activity in approved_activities:
            by_category[category_id_by_subcategory_id[activity.subcategory_id]].append(activity)

        def make_participation(student_id, activity, evidence_status):
            checked_in = evidence_status != EvidenceStatus.pending
            # A2: hours are derived from the activity and only counted once approved
            hours_earned = activity.hours if evidence_status == EvidenceStatus.approved else 0
            return Participation(
                student_id=student_id,
                activity_id=activity.id,
                check_in_time=activity.start_at if checked_in else None,
                hours_earned=hours_earned,
                evidence_status=evidence_status,
            )

        # --- participations: ชั่วโมงสะสมของแต่ละคนถูกกำหนดด้วย "กลุ่มเป้าหมาย" ตามชั้นปี ---
        participations = []
        # จำนวนผู้ลงทะเบียนต่อกิจกรรม — ใช้กันไม่ให้ลงทะเบียนเกินความจุ (เกิน 100%)
        registered_count: dict[int, int] = defaultdict(int)

        def with_room(candidates):
            return [a for a in candidates if registered_count[a.id] < a.max_participants]

        def register(student_id, activity, evidence_status):
            participations.append(make_participation(student_id, activity, evidence_status))
            registered_count[activity.id] += 1

        profile_of_student: dict[int, str] = {}
        students_by_year = defaultdict(list)
        for student in students:
            students_by_year[student.year_level].append(student)

        for year_level, year_students in students_by_year.items():
            weights = YEAR_PROFILE_WEIGHTS[year_level]
            profile_names = list(weights)
            profile_weights = [weights[name] for name in profile_names]
            profiles = list(GUARANTEED_PROFILES) + rng.choices(
                profile_names, weights=profile_weights, k=len(year_students) - len(GUARANTEED_PROFILES)
            )
            rng.shuffle(profiles)
            # นิสิตเดโม (คนแรกของปี 4) ตั้งใจให้ "เกือบผ่าน" — มีชั่วโมงพอให้ดูสวย
            # แต่ยังขาดบางหมวด จะได้เดโมคำถาม "ขาดหมวดไหน" กับแชตบอตได้
            if year_level == 4:
                profiles[0] = "near"

            for student, profile in zip(year_students, profiles):
                profile_of_student[student.id] = profile
                target = target_hours(profile, year_level, rng)

                approved_picks = []
                if target > 0:
                    ordered = with_room(_interleave_by_category(by_category, rng))
                    approved_picks, _ = _pick_activities_for_target(
                        ordered, target, allow_overshoot=(profile == "passed")
                    )
                    for activity in approved_picks:
                        register(student.id, activity, EvidenceStatus.approved)

                # แถวที่ยังรอตรวจ/ไม่ผ่าน ปนไว้ให้สมจริง (ไม่นับเข้าชั่วโมงสะสม)
                leftovers = with_room([a for a in approved_activities if a not in approved_picks])
                rng.shuffle(leftovers)
                extra_count = rng.choices([0, 1, 2, 3], weights=[25, 40, 25, 10])[0]
                for activity in leftovers[:extra_count]:
                    status = rng.choices(
                        [EvidenceStatus.pending, EvidenceStatus.rejected], weights=[7, 3]
                    )[0]
                    register(student.id, activity, status)

        # นิสิตเดโม (คนแรก = ปี 4) ต้องมีครบทั้ง approved / pending / rejected
        demo_student = students[0]
        demo_statuses = {
            p.evidence_status for p in participations if p.student_id == demo_student.id
        }
        used = {p.activity_id for p in participations if p.student_id == demo_student.id}
        for status in (EvidenceStatus.approved, EvidenceStatus.pending, EvidenceStatus.rejected):
            if status in demo_statuses:
                continue
            spare = next(
                (a for a in with_room(approved_activities) if a.id not in used), None
            )
            if spare is not None:
                register(demo_student.id, spare, status)
                used.add(spare.id)

        session.add_all(participations)
        session.commit()
        for p in participations:
            session.refresh(p)

        # --- กิจกรรมที่ตั้งใจให้ "เต็ม": ตั้งความจุเท่าจำนวนผู้ลงทะเบียนจริง
        #     เพื่อให้ participant_count >= max_participants (ปิดรับสมัคร) ---
        for activity in activities:
            if activity.name in FULL_ACTIVITY_NAMES and registered_count[activity.id] > 0:
                activity.max_participants = registered_count[activity.id]
                session.add(activity)
        session.commit()

        # --- Bronze evidence: every approved/rejected participation must have a real file (F2);
        #     plus ~half of the pending ones (uploaded, awaiting review) ---
        bucket = settings.minio_bucket_bronze
        try:
            # get_storage() itself can fail when the minio package is not installed
            # locally (STORAGE_BACKEND defaults to "minio"), so it lives in the try too.
            storage = get_storage()
            storage.ensure_bucket(bucket)
        except Exception as exc:  # noqa: BLE001
            print(f"เตือน: เชื่อม MinIO ไม่ได้ ({exc}) — บันทึก raw_file แต่ไม่อัปโหลดไฟล์จริง")
            storage = None

        # ใบประกาศวาดด้วยฟอนต์ไทย ถ้าเครื่องไม่มีฟอนต์ OCR จะอ่านไม่ออก (ตัวอักษรกลายเป็นกล่อง)
        font_path = find_thai_font()
        if font_path is None:
            print(
                "เตือน: ไม่พบฟอนต์ไทยในเครื่อง — ใบประกาศจะวาดด้วยฟอนต์ default และ OCR จะอ่านภาษาไทยไม่ออก\n"
                "       (ใน docker ติดตั้งผ่าน fonts-thai-tlwg ให้แล้ว)"
            )

        students_by_id = {s.id: s for s in students}
        activities_by_id = {a.id: a for a in activities}

        raw_files = []
        variant_counts: dict[str, int] = defaultdict(int)
        for p in participations:
            needs_evidence = p.evidence_status in (
                EvidenceStatus.approved,
                EvidenceStatus.rejected,
            ) or (p.evidence_status == EvidenceStatus.pending and rng.random() < 0.5)
            if not needs_evidence:
                continue

            student = students_by_id[p.student_id]
            activity = activities_by_id[p.activity_id]
            variant = pick_variant(rng)
            variant_counts[variant] += 1
            reference = f"TSU-{activity.id:03d}-{p.id:05d}-{uuid.uuid4().hex[:6].upper()}"
            # เลขอ้างอิงไม่ซ้ำ = ทุกไฟล์ checksum ต่างกัน ตัวตรวจไฟล์ซ้ำจึงไม่ติดธงผิด
            image_bytes = render_certificate(
                student_name=student.full_name,
                activity_name=activity.name,
                activity_date=activity.start_at,
                category_path=category_path_by_subcategory_id.get(activity.subcategory_id, "-"),
                reference=reference,
                variant=variant,
                font_path=font_path,
            )
            checksum = hashlib.sha256(image_bytes).hexdigest()

            now = datetime.utcnow()
            object_key = (
                f"evidence/year={now:%Y}/month={now:%m}"
                f"/activity_id={p.activity_id}/participation_id={p.id}"
                f"/{uuid.uuid4().hex}_seed.png"
            )
            if storage is not None:
                storage.upload_object(bucket, object_key, image_bytes, "image/png")
            raw_files.append(
                RawFile(
                    bucket=bucket,
                    object_key=object_key,
                    original_filename=f"certificate_{reference}.png",
                    content_type="image/png",
                    size_bytes=len(image_bytes),
                    checksum=checksum,
                    source_system="student_upload",
                    uploaded_by=None,
                    ingested_at=now,
                    participation_id=p.id,
                )
            )
        session.add_all(raw_files)
        session.commit()
        print(
            "หลักฐาน: ใบประกาศสมบูรณ์ {full} ใบ, ไม่มีชื่อผู้เข้าร่วม {no_name} ใบ, "
            "ภาพเบลอ/ความละเอียดต่ำ {low} ใบ".format(
                full=variant_counts[VARIANT_FULL],
                no_name=variant_counts[VARIANT_NO_NAME],
                low=variant_counts[VARIANT_LOW_QUALITY],
            )
        )

        # --- กิจกรรม "กำลังจัดอยู่ตอนนี้" สำหรับเดโมเช็กอินด้วย QR ---
        #
        # สร้างท้ายสุดโดยตั้งใจ: ไม่ให้เข้าไปอยู่ใน by_category ที่สุ่มการเข้าร่วม
        # ย้อนหลัง และไม่ให้เข้าลูปสร้างใบประกาศ Bronze — กิจกรรมที่เพิ่งเริ่ม
        # 30 นาทีย่อมยังไม่มีใครได้ใบประกาศหรือได้รับอนุมัติชั่วโมง
        live_activity = _upsert_live_activity(
            session,
            location=rng.choice(LOCATIONS),
            subcategory_id=subcategory_id_by_name[LIVE_ACTIVITY["subcategory_name"]],
            staff_user_id=staff_user.id,
            admin_user_id=admin_user.id,
        )
        activities.append(live_activity)

        # นิสิตกลุ่มแรกสมัครล่วงหน้าไว้ (ยังไม่เช็กอิน) — สแกนแล้วจะได้เส้นทาง
        # "อัปเดต participation เดิม" ส่วนคนอื่นที่ไม่ได้สมัครจะเป็น walk-up
        live_participations = [
            Participation(
                student_id=student.id,
                activity_id=live_activity.id,
                check_in_time=None,
                hours_earned=0,
                evidence_status=EvidenceStatus.pending,
            )
            for student in students[:LIVE_ACTIVITY_PREREGISTERED]
        ]
        session.add_all(live_participations)
        session.commit()
        participations.extend(live_participations)
        registered_count[live_activity.id] = len(live_participations)
        print(
            f"\nกิจกรรมเดโมเช็กอิน QR: \"{live_activity.name}\" "
            f"เริ่ม {live_activity.start_at:%Y-%m-%d %H:%M} เวลาไทย ({LIVE_ACTIVITY['hours']:g} ชม.) "
            f"— สมัครล่วงหน้าแล้ว {len(live_participations)} คน ที่เหลือสแกนเป็น walk-up ได้"
        )

        _print_summary(
            students=students,
            users=users,
            activities=activities,
            participations=participations,
            raw_files=raw_files,
            profile_of_student=profile_of_student,
            registered_count=registered_count,
            total_required_hours=total_required_hours,
        )


def _print_summary(
    *, students, users, activities, participations, raw_files, profile_of_student,
    registered_count, total_required_hours,
) -> None:
    """สรุปตัวเลขหลังรัน seed ให้ตรวจกับแดชบอร์ดได้ทันที"""
    hours_by_student = defaultdict(float)
    for p in participations:
        if p.evidence_status == EvidenceStatus.approved:
            hours_by_student[p.student_id] += p.hours_earned

    at_risk_threshold = total_required_hours * 0.5
    print(
        f"\nseed สำเร็จ: users={len(users)}, students={len(students)}, "
        f"activities={len(activities)}, participations={len(participations)}, "
        f"raw_files={len(raw_files)}"
    )
    print(f"เกณฑ์ผ่าน = {total_required_hours:g} ชม. | กลุ่มเสี่ยง = ต่ำกว่า {at_risk_threshold:g} ชม. (50%)\n")

    header = f"{'ชั้นปี':<8}{'จำนวน':>6}{'ผ่านเกณฑ์':>12}{'เกือบผ่าน':>12}{'กลุ่มเสี่ยง':>12}{'ยังไม่เริ่ม':>12}{'ชม.เฉลี่ย':>12}"
    print(header)
    print("-" * 76)
    totals = {"n": 0, "passed": 0, "near": 0, "at_risk": 0, "none": 0, "hours": 0.0}
    for year_level in (1, 2, 3, 4):
        year_students = [s for s in students if s.year_level == year_level]
        hours = [hours_by_student[s.id] for s in year_students]
        passed = sum(1 for h in hours if h >= total_required_hours)
        near = sum(1 for h in hours if at_risk_threshold <= h < total_required_hours)
        at_risk = sum(1 for h in hours if 0 < h < at_risk_threshold)
        none = sum(1 for h in hours if h == 0)
        avg = sum(hours) / len(hours) if hours else 0.0
        print(
            f"{f'ปี {year_level}':<8}{len(year_students):>6}{passed:>12}{near:>12}"
            f"{at_risk + none:>12}{none:>12}{avg:>12.1f}"
        )
        totals["n"] += len(year_students)
        totals["passed"] += passed
        totals["near"] += near
        totals["at_risk"] += at_risk
        totals["none"] += none
        totals["hours"] += sum(hours)
    print("-" * 76)
    all_at_risk = totals["at_risk"] + totals["none"]
    print(
        f"{'รวม':<8}{totals['n']:>6}{totals['passed']:>12}{totals['near']:>12}"
        f"{all_at_risk:>12}{totals['none']:>12}{totals['hours'] / totals['n']:>12.1f}"
    )
    print(
        f"\n% ผ่านเกณฑ์ = {totals['passed'] / totals['n'] * 100:.1f}%  |  "
        f"กลุ่มเสี่ยง (<50%) = {all_at_risk} คน ({all_at_risk / totals['n'] * 100:.1f}%)"
    )

    approved_acts = [a for a in activities if a.approval_status == ApprovalStatus.approved]
    full = [a for a in approved_acts if registered_count[a.id] >= a.max_participants]
    print(
        f"กิจกรรม: อนุมัติแล้ว {len(approved_acts)} | รออนุมัติ "
        f"{len(activities) - len(approved_acts)} | เปิดรับสมัคร {len(approved_acts) - len(full)} | "
        f"เต็มแล้ว {len(full)}"
    )
    status_counts = defaultdict(int)
    for p in participations:
        status_counts[p.evidence_status.value] += 1
    print(
        "การเข้าร่วม: " + ", ".join(f"{k}={v}" for k, v in sorted(status_counts.items()))
    )
    demo = students[0]
    print(
        f"\nตัวอย่างล็อกอินนิสิต (username = รหัสนิสิต, password = รหัสนิสิต): "
        f"{demo.student_id} / {demo.student_id} "
        f"({demo.full_name}, ปี {demo.year_level}, {hours_by_student[demo.id]:g} ชม.)"
    )


if __name__ == "__main__":
    if "--refresh-live" in sys.argv:
        refresh_live_activity()
    else:
        seed()
