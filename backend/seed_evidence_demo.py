"""หลักฐานเดโมสำหรับหน้า "ตรวจหลักฐาน" (OCR review)

การเข้าร่วมจากเฟส 5 (``seed_participations.py``) เป็น approved ทั้งหมดและไม่มีไฟล์หลักฐานเลย
คิวตรวจหลักฐานจึงว่าง สคริปต์นี้เติมการเข้าร่วมใหม่ของนิสิตจริงจำนวนหนึ่ง (ค่าเริ่ม 24 ราย)
ในกิจกรรมที่จัดไปแล้ว พร้อมใบประกาศที่วาดจริง (Bronze) แล้วส่งผ่าน Silver pipeline ตัวจริง:

* ``full``           ใบสมบูรณ์                    → คาดว่า auto_approved (ระบบให้ชั่วโมงเอง)
* ``no_name``        ใบที่ไม่มีชื่อผู้เข้าร่วม        → คาดว่า needs_review
* ``low_quality``    ภาพถ่ายเบลอ                 → คาดว่า needs_review
* ``pdf_text``       PDF ที่ export จากโปรแกรม (มี text layer) → อ่านข้อความตรง ข้าม OCR (เฟส 3B)
* ``pdf_scan``       PDF สแกน (ภาพล้วน) → render + OCR จริง ได้ decision ตามคะแนน (เฟส 3B)
* ``template_base``  เกียรติบัตรเทมเพลต "แบนเนอร์" ของนิสิตคนหนึ่ง → decision ตามคะแนน OCR
* ``template_twin``  เทมเพลตเดียวกันของอีกคน คนละกิจกรรม — pHash ใกล้ ``template_base`` แต่ข้อความ
                     ต่างกันชัด → text veto ต้องกันไว้ ไม่ flag (เคส B ของเฟส 3C)
* ``duplicate``      ไฟล์เดียวกับใบของเพื่อนที่อนุมัติแล้ว → flagged exact (เคส C)
* ``near_duplicate`` ใบของเพื่อนที่ย่อ+บีบอัด JPEG ใหม่ ชื่อเจ้าของเดิม → flagged near (เคส A, pHash — เฟส 3A)

decision ของสามแบบแรกมาจาก OCR จริง จึงอาจไม่ตรงที่คาดทุกใบ (สรุปยอดจริงให้ตอนจบ)
ส่วน flagged การันตีได้ เพราะตัดสินจาก checksum ไม่ใช่จาก OCR — ใบ "ต้นฉบับ" ถูกแนบให้
การเข้าร่วมที่อนุมัติไปแล้วของเจ้าของใบ (ไม่แตะชั่วโมงของเจ้าของ)

เลือกเฉพาะนิสิตที่ "ผ่าน" ตามไฟล์ เพื่อไม่ให้สถานะ ผ่าน/ไม่ผ่าน เปลี่ยน (check_completion ยังตรง)
และเคารพที่นั่ง/เวลาชนแบบเดียวกับการสมัครจริง

รันในคอนเทนเนอร์ (มีฟอนต์ไทย + easyocr + MinIO):
    docker compose exec -T backend python seed_evidence_demo.py
    docker compose exec -T backend python seed_evidence_demo.py --reset    # ลบเดโมเดิมแล้วสร้างใหม่
    docker compose exec -T backend python seed_evidence_demo.py --remove   # ลบเดโมอย่างเดียว
"""
from __future__ import annotations

import argparse
import hashlib
import io
import random
import sys
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Callable, Optional

from sqlmodel import Session, func, or_, select

from app import silver
from app.config import settings
from app.database import create_db_and_tables, engine
from app.models import (
    Activity,
    ActivityRequirement,
    ApprovalStatus,
    EvidenceStatus,
    ImportedCompletion,
    OcrDecision,
    Participation,
    RawFile,
    Requirement,
    SilverEvidenceOcr,
    Student,
    StudentStatus,
    User,
)
from app.ocr import OcrEngine, get_ocr
from app.phash import compute_phash, phash_distance
from app.storage import ObjectStorage, get_storage
from seed_evidence import (
    VARIANT_FULL,
    VARIANT_LOW_QUALITY,
    VARIANT_NO_NAME,
    find_thai_font,
    render_certificate,
    thai_date,
)

# ป้าย source_system ของไฟล์เดโม — ใช้หาไฟล์ของสคริปต์นี้ตอน --reset/--remove
SOURCE_DEMO = "seed_demo"  # การเข้าร่วมที่สคริปต์สร้าง (ลบทิ้งทั้งแถวได้)
SOURCE_DEMO_ORIGINAL = "seed_demo_original"  # ใบต้นฉบับที่แนบให้การเข้าร่วมเดิม (ลบแค่ไฟล์)
DEMO_SOURCES = (SOURCE_DEMO, SOURCE_DEMO_ORIGINAL)

VARIANT_DUPLICATE = "duplicate"
VARIANT_NEAR_DUPLICATE = "near_duplicate"
VARIANT_PDF_TEXT = "pdf_text"
VARIANT_PDF_SCAN = "pdf_scan"
VARIANT_TEMPLATE_BASE = "template_base"
VARIANT_TEMPLATE_TWIN = "template_twin"
VARIANT_ORDER = (
    VARIANT_FULL,
    VARIANT_NO_NAME,
    VARIANT_LOW_QUALITY,
    VARIANT_PDF_TEXT,
    VARIANT_PDF_SCAN,
    VARIANT_TEMPLATE_BASE,
    VARIANT_TEMPLATE_TWIN,
    VARIANT_DUPLICATE,
    VARIANT_NEAR_DUPLICATE,
)
# แบบที่ใช้ใบของ "เพื่อน" (ต้องมีใบต้นฉบับที่อนุมัติแล้ว)
COPY_VARIANTS = (VARIANT_DUPLICATE, VARIANT_NEAR_DUPLICATE)
# คู่เทมเพลตเดียวกันคนละคน (เคส B) — สร้างเป็นคู่ในบล็อกของตัวเอง
TEMPLATE_VARIANTS = (VARIANT_TEMPLATE_BASE, VARIANT_TEMPLATE_TWIN)
# fixture ของเฟส 3 มีอย่างละหนึ่งใบเสมอ ไม่คิดตามสัดส่วน
SINGLE_VARIANTS = (
    VARIANT_PDF_TEXT, VARIANT_PDF_SCAN, VARIANT_TEMPLATE_BASE, VARIANT_TEMPLATE_TWIN, VARIANT_NEAR_DUPLICATE,
)

# 29 = 24 ใบแบบเดิม (full 11 / no_name 5 / low_quality 4 / duplicate 4 เท่าเดิม) + fixture เฟส 3 อีก 5
DEFAULT_COUNT = 29
DEFAULT_SEED = 20260914
MIN_COUNT = 9  # น้อยกว่านี้ได้ไม่ครบทุกแบบ

# คู่เคส B ต้องเข้าชั้น near แน่ ๆ (ไม่ใช่เฉียด threshold) — pHash ห่างไม่เกิน threshold ลบค่านี้
TEMPLATE_TWIN_MARGIN_BITS = 4

# สำเนา near_duplicate: ย่อเหลือ 75% แล้วบันทึก JPEG คุณภาพ 70 — checksum ต่าง แต่ pHash ห่างไม่กี่บิต
NEAR_COPY_SCALE = 0.75
NEAR_COPY_JPEG_QUALITY = 70


class SeedAborted(Exception):
    """หยุดโดยไม่เขียนอะไรลงฐาน (ผู้เรียก rollback)"""


@dataclass
class Report:
    planned: Counter = field(default_factory=Counter)
    # variant -> Counter(decision)
    decisions: dict[str, Counter] = field(default_factory=lambda: defaultdict(Counter))
    participations: int = 0
    hours_granted: float = 0.0

    def total(self) -> Counter:
        total: Counter = Counter()
        for counter in self.decisions.values():
            total.update(counter)
        return total


def plan_variants(count: int) -> list[str]:
    """แบ่ง [count] ใบเป็นแต่ละแบบ — ใบสมบูรณ์ราวครึ่งหนึ่ง ที่เหลือเป็นเคสให้คนตรวจ"""
    if count < MIN_COUNT:
        raise SeedAborted(f"ต้องมีอย่างน้อย {MIN_COUNT} รายการ ถึงจะมีครบทุกแบบ")
    # สัดส่วนคิดจากส่วนที่เหลือหลังหัก fixture เฟส 3 — ชุดเดิมจึงได้จำนวนเท่าเดิมทุกแบบ
    base = count - len(SINGLE_VARIANTS)
    duplicate = max(1, round(base * 0.15))
    low_quality = max(1, round(base * 0.15))
    no_name = max(1, round(base * 0.2))
    full = base - duplicate - low_quality - no_name
    if full < 1:
        raise SeedAborted(f"ต้องมีอย่างน้อย {MIN_COUNT} รายการ ถึงจะมีครบทุกแบบ")
    # ใบของตัวเองก่อน ใบของเพื่อนไว้ท้าย — pipeline ประมวลผลตามลำดับนี้ ใบที่ถูกเทียบจึงมาก่อนเสมอ
    # (template_base มาก่อน template_twin · ใบต้นฉบับมาก่อนสำเนา)
    return (
        [VARIANT_FULL] * full
        + [VARIANT_NO_NAME] * no_name
        + [VARIANT_LOW_QUALITY] * low_quality
        + [VARIANT_PDF_TEXT, VARIANT_PDF_SCAN]
        + [VARIANT_TEMPLATE_BASE, VARIANT_TEMPLATE_TWIN]
        + [VARIANT_DUPLICATE] * duplicate
        + [VARIANT_NEAR_DUPLICATE]
    )


def has_demo_data(session: Session) -> bool:
    return (
        session.exec(
            select(RawFile.id).where(RawFile.source_system.in_(DEMO_SOURCES)).limit(1)
        ).first()
        is not None
    )


def _end_at(activity: Activity) -> datetime:
    return activity.start_at + timedelta(hours=activity.hours or 1)


class _Bookings:
    """กิจกรรมที่นิสิตแต่ละคนลงไว้แล้ว — กันลงซ้ำและกันเวลาชน (โหลดเฉพาะคนที่ถาม)"""

    def __init__(self, session: Session):
        self._session = session
        self._joined: dict[int, set[int]] = {}
        self._activities: dict[int, Activity] = {}

    def _activity(self, activity_id: int) -> Optional[Activity]:
        if activity_id not in self._activities:
            self._activities[activity_id] = self._session.get(Activity, activity_id)
        return self._activities[activity_id]

    def _load(self, student_id: int) -> set[int]:
        if student_id not in self._joined:
            self._joined[student_id] = set(
                self._session.exec(
                    select(Participation.activity_id).where(Participation.student_id == student_id)
                ).all()
            )
        return self._joined[student_id]

    def can_join(self, student_id: int, activity: Activity) -> bool:
        joined = self._load(student_id)
        if activity.id in joined:
            return False
        for other_id in joined:
            other = self._activity(other_id)
            if other and other.start_at < _end_at(activity) and activity.start_at < _end_at(other):
                return False
        return True

    def add(self, student_id: int, activity_id: int) -> None:
        self._load(student_id).add(activity_id)


def _category_label(session: Session, activity: Activity) -> str:
    names = session.exec(
        select(Requirement.name)
        .join(ActivityRequirement, ActivityRequirement.requirement_id == Requirement.id)
        .where(ActivityRequirement.activity_id == activity.id)
        .order_by(Requirement.id)
    ).all()
    return " · ".join(names) if names else activity.activity_type


def _reference(activity: Activity, participation: Participation) -> str:
    # เลขอ้างอิงไม่ซ้ำ = checksum ต่างกันทุกใบ (ยกเว้นเคส duplicate ที่ตั้งใจใช้ไฟล์เดียวกัน)
    return f"TSU-{activity.id:03d}-{participation.id:05d}-{uuid.uuid4().hex[:6].upper()}"


_EXTENSIONS = {"image/png": "png", "image/jpeg": "jpg", "application/pdf": "pdf"}


def _attach_file(
    session: Session,
    storage: ObjectStorage,
    participation: Participation,
    data: bytes,
    *,
    reference: str,
    source: str,
    uploaded_by: Optional[int],
    ingested_at: datetime,
    content_type: str = "image/png",
) -> RawFile:
    """เขียนไฟล์ลง Bronze ตามโครง path เดียวกับการอัปโหลดจริง (รวม checksum + pHash แบบเดียวกัน)"""
    extension = _EXTENSIONS[content_type]
    bucket = settings.minio_bucket_bronze
    object_key = (
        f"evidence/year={ingested_at:%Y}/month={ingested_at:%m}"
        f"/activity_id={participation.activity_id}"
        f"/participation_id={participation.id}"
        f"/{uuid.uuid4().hex}_certificate.{extension}"
    )
    storage.upload_object(bucket, object_key, data, content_type)
    raw_file = RawFile(
        bucket=bucket,
        object_key=object_key,
        original_filename=f"certificate_{reference}.{extension}",
        content_type=content_type,
        size_bytes=len(data),
        checksum=hashlib.sha256(data).hexdigest(),
        # เหมือนการอัปโหลดจริง — ไม่มี pHash ชั้นภาพเกือบเหมือนจะจับสำเนาไม่ได้
        phash=compute_phash(data, content_type),
        source_system=source,
        uploaded_by=uploaded_by,
        ingested_at=ingested_at,
        participation_id=participation.id,
    )
    session.add(raw_file)
    return raw_file


def certificate_text_pdf(
    *,
    student_name: str,
    activity_name: str,
    activity_date: datetime,
    category_path: str,
    reference: str,
    font_path: Optional[str],
) -> bytes:
    """เกียรติบัตรแบบ PDF ที่ export จากโปรแกรม — ข้อความเป็น vector จึงมี text layer

    ต้องมีฟอนต์ไทยถึงจะฝังข้อความไทยได้ ไม่มีก็ใช้ฟอนต์ในตัว (ข้อความจะอ่านไม่ออก → OCR แทน)
    """
    import pymupdf

    width, height = 842, 595  # A4 แนวนอน
    doc = pymupdf.open()
    page = doc.new_page(width=width, height=height)
    page.draw_rect(pymupdf.Rect(20, 20, width - 20, height - 20), color=(0.12, 0.24, 0.48), width=4)
    page.draw_rect(pymupdf.Rect(32, 32, width - 32, height - 32), color=(0.79, 0.64, 0.15), width=1.5)
    font = pymupdf.Font(fontfile=font_path) if font_path else pymupdf.Font("helv")
    font_kwargs = {"fontname": "thai", "fontfile": font_path} if font_path else {}
    lines = [
        ("มหาวิทยาลัยทักษิณ", 26),
        ("เกียรติบัตรฉบับนี้ให้ไว้เพื่อแสดงว่า", 20),
        (student_name, 32),
        ("ได้เข้าร่วมกิจกรรม", 20),
        (activity_name, 26),
        (f"หมวด {category_path}", 16),
        (f"จัดขึ้นเมื่อวันที่ {thai_date(activity_date)}", 18),
        (f"เลขที่อ้างอิง {reference}", 14),
    ]
    y = 95.0
    for text, size in lines:
        x = max(40.0, (width - font.text_length(text, fontsize=size)) / 2)
        page.insert_text((x, y), text, fontsize=size, **font_kwargs)
        y += size * 2.1
    data = doc.tobytes()
    doc.close()
    return data


def scanned_pdf(image_png: bytes, dpi: int) -> bytes:
    """PDF สแกน — ภาพเต็มหน้า ไม่มี text layer

    ขนาดหน้าตั้งให้ render ที่ [dpi] ได้ความละเอียดเท่าภาพเดิม (ไม่ถูกขยายจนเบลอ) เหมือนเครื่อง
    สแกนที่บันทึกไฟล์ที่ DPI นั้นจริง
    """
    import pymupdf
    from PIL import Image

    with Image.open(io.BytesIO(image_png)) as image:
        width_px, height_px = image.size
    doc = pymupdf.open()
    page = doc.new_page(width=width_px * 72 / dpi, height=height_px * 72 / dpi)
    page.insert_image(page.rect, stream=image_png)
    data = doc.tobytes()
    doc.close()
    return data


def near_copy(image_png: bytes) -> bytes:
    """สำเนาที่ย่อแล้วบันทึก JPEG ใหม่ — ไฟล์คนละไบต์ (checksum ต่าง) แต่ภาพคล้ายกันมาก (pHash ใกล้)"""
    from PIL import Image

    with Image.open(io.BytesIO(image_png)) as image:
        rgb = image.convert("RGB")
        smaller = rgb.resize((int(rgb.width * NEAR_COPY_SCALE), int(rgb.height * NEAR_COPY_SCALE)))
    buffer = io.BytesIO()
    smaller.save(buffer, format="JPEG", quality=NEAR_COPY_JPEG_QUALITY)
    return buffer.getvalue()


def render_banner_certificate(
    *,
    student_name: str,
    activity_name: str,
    location: str,
    category_path: str,
    activity_date: datetime,
    reference: str,
    font_path: Optional[str],
) -> bytes:
    """เกียรติบัตรเทมเพลต "แบนเนอร์" — กราฟิกใหญ่ครองภาพ ตัวอักษรเล็ก (เคส B ของเฟส 3C)

    pHash ดูโครงภาพความถี่ต่ำเป็นหลัก เทมเพลตแบบนี้ของคนละคนจึงได้ pHash ใกล้กัน (วัดใน container
    15 คู่ ห่าง 6–16 บิต จาก 256) ขณะที่ข้อความแทบไม่ซ้ำกันเลย (ชื่อ/กิจกรรม/สถานที่/หมวด/วันที่
    ความคล้ายของ OCR 0.36) — เคสที่ text veto ต้องกันไม่ให้ flag ผิด
    """
    from PIL import Image, ImageDraw, ImageFont

    width, height = 1000, 700
    image = Image.new("RGB", (width, height), "#e9dcc0")
    draw = ImageDraw.Draw(image)

    def font(size: int):
        return ImageFont.truetype(font_path, size) if font_path else ImageFont.load_default()

    draw.rectangle([0, 0, width, 250], fill="#0f2f58")
    draw.ellipse([40, 30, 240, 230], fill="#d4a017")
    draw.ellipse([85, 75, 195, 185], fill="#0f2f58")
    draw.polygon([(width, 250), (width - 330, height), (width, height)], fill="#0f2f58")
    draw.polygon([(width, 330), (width - 180, height), (width, height)], fill="#d4a017")
    draw.rectangle([0, 620, width, height], fill="#d4a017")
    draw.text((290, 85), "เกียรติบัตร", font=font(76), fill="white")
    for text, size, y in (
        (student_name, 32, 280),
        (activity_name, 24, 335),
        (location, 20, 380),
        (category_path, 20, 415),
        (thai_date(activity_date), 20, 450),
        (reference, 18, 560),
    ):
        draw.text((70, y), text, font=font(size), fill="#2b2b2b")
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def _own_evidence(
    session: Session,
    variant: str,
    student: Student,
    activity: Activity,
    reference: str,
    font_path: Optional[str],
) -> tuple[bytes, str]:
    """ไฟล์หลักฐานของนิสิตเอง ตามแบบ — คืน (bytes, content_type)"""
    fields = dict(
        student_name=student.full_name,
        activity_name=activity.name,
        activity_date=activity.start_at,
        category_path=_category_label(session, activity),
        reference=reference,
    )
    if variant == VARIANT_PDF_TEXT:
        return certificate_text_pdf(**fields, font_path=font_path or find_thai_font()), "application/pdf"
    image_variant = VARIANT_FULL if variant == VARIANT_PDF_SCAN else variant
    png = render_certificate(**fields, variant=image_variant, font_path=font_path)
    if variant == VARIANT_PDF_SCAN:
        return scanned_pdf(png, settings.ocr_pdf_dpi), "application/pdf"
    return png, "image/png"


def populate(
    session: Session,
    storage: ObjectStorage,
    ocr: OcrEngine,
    *,
    now: datetime,
    count: int = DEFAULT_COUNT,
    seed: int = DEFAULT_SEED,
    font_path: Optional[str] = None,
    log: Callable[[str], None] = print,
) -> Report:
    """สร้างการเข้าร่วม + ไฟล์หลักฐาน แล้วรัน OCR (Silver) ทีละใบ

    commit เองสองจังหวะ: หลังสร้างแถว/ไฟล์ครบ และทุกใบที่ OCR เสร็จ (pipeline commit เอง)
    """
    if has_demo_data(session):
        raise SeedAborted("มีหลักฐานเดโมอยู่แล้ว — ใช้ --reset ถ้าจะสร้างใหม่")
    variants = plan_variants(count)
    rng = random.Random(seed)
    report = Report(planned=Counter(variants))
    storage.ensure_bucket(settings.minio_bucket_bronze)

    # กิจกรรมที่จบไปแล้วอย่างน้อยหนึ่งวัน — ส่งหลักฐานหลังงานจบได้สมจริง
    cutoff = now - timedelta(days=1)
    activities = [
        a
        for a in session.exec(
            select(Activity)
            .where(Activity.approval_status == ApprovalStatus.approved, Activity.is_hidden == False)  # noqa: E712
            .order_by(Activity.id)
        ).all()
        if _end_at(a) <= cutoff
    ]
    if not activities:
        raise SeedAborted("ไม่มีกิจกรรมที่จัดไปแล้ว — รัน seed_activities_2567.py ก่อน")
    activities_by_id = {a.id: a for a in activities}

    # ไม่เอานิสิตที่ "ไม่ผ่าน" ตามไฟล์ — auto_approve เพิ่มชั่วโมงแล้วสถานะอาจพลิก
    students = list(
        session.exec(
            select(Student)
            .where(
                Student.status == StudentStatus.active,
                or_(
                    Student.imported_completion.is_(None),
                    Student.imported_completion != ImportedCompletion.failed,
                ),
            )
            .order_by(Student.id)
        ).all()
    )
    if len(students) <= count:
        raise SeedAborted(f"นิสิตมีแค่ {len(students)} คน ไม่พอสำหรับ {count} รายการ")
    rng.shuffle(students)
    user_by_student = dict(
        session.exec(select(User.student_id, User.id).where(User.student_id.is_not(None))).all()
    )

    seats = dict(
        session.exec(
            select(Participation.activity_id, func.count()).group_by(Participation.activity_id)
        ).all()
    )
    bookings = _Bookings(session)
    used_students: set[int] = set()

    def has_room(activity: Activity) -> bool:
        return seats.get(activity.id, 0) < activity.max_participants

    def upload_time(activity: Activity, extra_hours: int = 0) -> datetime:
        uploaded = _end_at(activity) + timedelta(hours=rng.randint(1, 12) + extra_hours)
        return min(uploaded, now - timedelta(minutes=5))

    def book(student: Student, activity: Activity) -> Participation:
        participation = Participation(
            student_id=student.id,
            activity_id=activity.id,
            check_in_time=activity.start_at - timedelta(minutes=rng.randint(0, 20)),
            hours_earned=0,
            evidence_status=EvidenceStatus.pending,
        )
        session.add(participation)
        session.flush()
        seats[activity.id] = seats.get(activity.id, 0) + 1
        bookings.add(student.id, activity.id)
        used_students.add(student.id)
        return participation

    demo: list[tuple[str, Participation]] = []

    # --- ใบของตัวเอง: สมบูรณ์ / ไม่มีชื่อ / เบลอ ---
    candidates = iter(students)
    for variant in (v for v in variants if v not in COPY_VARIANTS + TEMPLATE_VARIANTS):
        while True:
            student = next(candidates, None)
            if student is None:
                raise SeedAborted("หากิจกรรมที่ยังมีที่นั่งและเวลาไม่ชนให้นิสิตไม่พอ")
            options = [a for a in activities if has_room(a)]
            rng.shuffle(options)
            activity = next((a for a in options if bookings.can_join(student.id, a)), None)
            if activity is not None:
                break
        participation = book(student, activity)
        reference = _reference(activity, participation)
        data, content_type = _own_evidence(session, variant, student, activity, reference, font_path)
        _attach_file(
            session, storage, participation, data,
            reference=reference, source=SOURCE_DEMO,
            uploaded_by=user_by_student.get(student.id), ingested_at=upload_time(activity),
            content_type=content_type,
        )
        demo.append((variant, participation))

    # --- เคส B: เทมเพลตแบนเนอร์เดียวกัน คนละคน คนละกิจกรรม ---
    # pHash ใกล้กัน (เข้าชั้น near) แต่ข้อความ OCR ต่างกันชัด → text veto ต้องกันไว้ ไม่ flag
    # เลือกคู่ที่ pHash ห่างไม่เกิน threshold − margin เพื่อให้แน่ใจว่าถึงขั้น veto จริง ไม่ใช่หลุด threshold เอง
    template_font = font_path or find_thai_font()
    template_hash: Optional[str] = None
    template_activities: set[int] = set()
    for variant in (v for v in variants if v in TEMPLATE_VARIANTS):
        placed = False
        while not placed:
            student = next(candidates, None)
            if student is None:
                raise SeedAborted("สร้างคู่เกียรติบัตรเทมเพลตเดียวกัน (เคส B) ที่ pHash ใกล้พอไม่ได้")
            options = [
                a for a in activities
                if has_room(a) and a.id not in template_activities and bookings.can_join(student.id, a)
            ]
            rng.shuffle(options)
            for activity in options:
                marker = "TB" if variant == VARIANT_TEMPLATE_BASE else "TT"
                reference = f"TSU-{activity.id:03d}-{marker}{uuid.uuid4().hex[:6].upper()}"
                png = render_banner_certificate(
                    student_name=student.full_name,
                    activity_name=activity.name,
                    location=activity.location,
                    category_path=_category_label(session, activity),
                    activity_date=activity.start_at,
                    reference=reference,
                    font_path=template_font,
                )
                phash = compute_phash(png, "image/png")
                if template_hash is not None and (
                    phash is None
                    or phash_distance(template_hash, phash)
                    > settings.ocr_phash_near_bits - TEMPLATE_TWIN_MARGIN_BITS
                ):
                    continue
                participation = book(student, activity)
                _attach_file(
                    session, storage, participation, png,
                    reference=reference, source=SOURCE_DEMO,
                    uploaded_by=user_by_student.get(student.id), ingested_at=upload_time(activity),
                )
                demo.append((variant, participation))
                template_activities.add(activity.id)
                template_hash = template_hash or phash
                placed = True
                break

    # --- ใบของเพื่อน: เอาใบของเจ้าของที่อนุมัติไปแล้วมาส่งเป็นของตัวเอง ---
    # duplicate = ไฟล์เดียวกันเป๊ะ (checksum) · near_duplicate = ย่อ+บีบอัดใหม่ (pHash)
    copies = [v for v in variants if v in COPY_VARIANTS]
    needed = len(copies)
    with_file = select(RawFile.participation_id).where(RawFile.participation_id.is_not(None))
    originals = list(
        session.exec(
            select(Participation)
            .where(
                Participation.evidence_status == EvidenceStatus.approved,
                Participation.activity_id.in_(list(activities_by_id)),
                ~Participation.id.in_(with_file),
            )
            .order_by(Participation.id)
            .limit(2000)
        ).all()
    )
    rng.shuffle(originals)
    made = 0
    for original in originals:
        if made == needed:
            break
        activity = activities_by_id[original.activity_id]
        if not has_room(activity) or original.student_id in used_students:
            continue
        borrower = next(
            (
                s
                for s in students
                if s.id not in used_students
                and s.id != original.student_id
                and bookings.can_join(s.id, activity)
            ),
            None,
        )
        if borrower is None:
            continue
        owner = session.get(Student, original.student_id)
        reference = _reference(activity, original)
        image = render_certificate(
            student_name=owner.full_name,
            activity_name=activity.name,
            activity_date=activity.start_at,
            category_path=_category_label(session, activity),
            reference=reference,
            variant=VARIANT_FULL,
            font_path=font_path,
        )
        used_students.add(owner.id)
        _attach_file(
            session, storage, original, image,
            reference=reference, source=SOURCE_DEMO_ORIGINAL,
            uploaded_by=user_by_student.get(owner.id), ingested_at=upload_time(activity),
        )
        participation = book(borrower, activity)
        variant = copies[made]
        if variant == VARIANT_NEAR_DUPLICATE:
            copy, content_type = near_copy(image), "image/jpeg"  # checksum ต่าง pHash ใกล้
        else:
            copy, content_type = image, "image/png"  # bytes เดียวกันเป๊ะ → checksum ตรง
        _attach_file(
            session, storage, participation, copy,
            reference=reference, source=SOURCE_DEMO,
            uploaded_by=user_by_student.get(borrower.id),
            ingested_at=upload_time(activity, extra_hours=12),
            content_type=content_type,
        )
        demo.append((variant, participation))
        made += 1
    if made < needed:
        raise SeedAborted(f"หาใบที่อนุมัติแล้วมาทำเคสไฟล์ซ้ำได้แค่ {made}/{needed}")

    session.commit()
    report.participations = len(demo)

    # --- Silver: OCR + decision ด้วย pipeline ตัวจริง (ไฟล์ซ้ำอยู่ท้ายลิสต์อยู่แล้ว) ---
    for index, (variant, participation) in enumerate(demo, 1):
        row = silver.process_participation_evidence(session, ocr, storage, participation.id)
        decision = OcrDecision(row.decision)
        report.decisions[variant][decision.value] += 1
        if decision == OcrDecision.auto_approved:
            session.refresh(participation)
            report.hours_granted += participation.hours_earned
        log(
            f"  [{index:>2}/{len(demo)}] {variant:<11} → {decision.value:<13} "
            f"(มั่นใจ {row.ocr_confidence:.2f} · ตรง {row.match_score:.2f})"
        )
    return report


def remove_demo(session: Session, storage: ObjectStorage) -> tuple[int, int]:
    """ลบของเดโม (ไม่ commit) — คืน (จำนวนการเข้าร่วมที่ลบ, จำนวนไฟล์ที่ลบ)

    การเข้าร่วมเดิมที่ถูกแนบใบต้นฉบับยังอยู่ครบ ลบแค่ไฟล์กับผล OCR ของมัน
    """
    files = list(session.exec(select(RawFile).where(RawFile.source_system.in_(DEMO_SOURCES))).all())
    demo_ids = {f.participation_id for f in files if f.source_system == SOURCE_DEMO and f.participation_id}
    if demo_ids:
        # ไฟล์ที่อัปโหลดทับทีหลังผ่านหน้าเว็บก็ต้องไปด้วย ไม่งั้นลบการเข้าร่วมไม่ได้ (FK)
        files += session.exec(
            select(RawFile).where(
                RawFile.participation_id.in_(demo_ids), RawFile.source_system.not_in(DEMO_SOURCES)
            )
        ).all()
    file_ids = [f.id for f in files]
    if not file_ids:
        return 0, 0

    for row in session.exec(
        select(SilverEvidenceOcr).where(
            or_(
                SilverEvidenceOcr.raw_file_id.in_(file_ids),
                SilverEvidenceOcr.participation_id.in_(demo_ids),
            )
        )
    ).all():
        session.delete(row)
    session.flush()

    for raw_file in files:
        try:
            storage.remove_object(raw_file.bucket, raw_file.object_key)
        except Exception:  # noqa: BLE001 - ไฟล์หายไปก่อนแล้วก็ไม่เป็นไร ลบแถวต่อ
            pass
        session.delete(raw_file)
    session.flush()

    for participation_id in demo_ids:
        participation = session.get(Participation, participation_id)
        if participation is not None:
            session.delete(participation)
    session.flush()
    return len(demo_ids), len(files)


def _print_report(report: Report) -> None:
    print(f"\nสร้างการเข้าร่วมพร้อมหลักฐาน {report.participations} ราย")
    for variant in VARIANT_ORDER:
        got = report.decisions.get(variant, Counter())
        detail = ", ".join(f"{d}={n}" for d, n in sorted(got.items())) or "-"
        print(f"  {variant:<11} {report.planned[variant]:>2} ใบ → {detail}")
    total = report.total()
    print(
        "รวม decision: "
        + ", ".join(f"{d.value}={total[d.value]}" for d in OcrDecision)
    )
    print(f"ชั่วโมงที่ระบบอนุมัติอัตโนมัติให้: {report.hours_granted:g} ชม.")
    if total[OcrDecision.auto_approved.value] == 0:
        print(
            "  ! ไม่มีใบไหน auto_approved — ตรวจว่า OCR_BACKEND=easyocr และมีฟอนต์ไทย "
            "(StubOcr อ่านได้ข้อความว่างเสมอ)"
        )


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="หลักฐานเดโมสำหรับหน้าตรวจหลักฐาน (OCR review)")
    parser.add_argument("--count", type=int, default=DEFAULT_COUNT, help="จำนวนการเข้าร่วมที่มีหลักฐาน")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED, help="seed ของการสุ่ม")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--reset", action="store_true", help="ลบเดโมเดิมแล้วสร้างใหม่")
    mode.add_argument("--remove", action="store_true", help="ลบเดโมอย่างเดียว")
    args = parser.parse_args(argv)

    create_db_and_tables()
    storage = get_storage()
    with Session(engine) as session:
        if args.reset or args.remove:
            participations, files = remove_demo(session, storage)
            session.commit()
            print(f"ลบเดโมเดิม: การเข้าร่วม {participations} ราย · ไฟล์ {files} ไฟล์")
            if args.remove:
                return 0

        font_path = find_thai_font()
        if font_path is None:
            print("เตือน: ไม่พบฟอนต์ไทย — OCR จะอ่านใบประกาศไม่ออก (ใน docker มีฟอนต์ให้แล้ว)")
        print(f"OCR backend: {settings.ocr_backend} — บน CPU ใช้ใบละหลายวินาที")
        try:
            report = populate(
                session, storage, get_ocr(),
                now=datetime.utcnow(), count=args.count, seed=args.seed, font_path=font_path,
            )
        except SeedAborted as exc:
            session.rollback()
            print(f"หยุด: {exc}")
            return 1

    _print_report(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
