"""หลักฐานเดโมสำหรับหน้า "ตรวจหลักฐาน" (OCR review)

การเข้าร่วมจากเฟส 5 (``seed_participations.py``) เป็น approved ทั้งหมดและไม่มีไฟล์หลักฐานเลย
คิวตรวจหลักฐานจึงว่าง สคริปต์นี้เติมการเข้าร่วมใหม่ของนิสิตจริงจำนวนหนึ่ง (ค่าเริ่ม 24 ราย)
ในกิจกรรมที่จัดไปแล้ว พร้อมใบประกาศที่วาดจริง (Bronze) แล้วส่งผ่าน Silver pipeline ตัวจริง:

* ``full``         ใบสมบูรณ์                    → คาดว่า auto_approved (ระบบให้ชั่วโมงเอง)
* ``no_name``      ใบที่ไม่มีชื่อผู้เข้าร่วม        → คาดว่า needs_review
* ``low_quality``  ภาพถ่ายเบลอ                 → คาดว่า needs_review
* ``duplicate``    ไฟล์เดียวกับใบของเพื่อนที่อนุมัติแล้ว → flagged

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
from app.storage import ObjectStorage, get_storage
from seed_evidence import (
    VARIANT_FULL,
    VARIANT_LOW_QUALITY,
    VARIANT_NO_NAME,
    find_thai_font,
    render_certificate,
)

# ป้าย source_system ของไฟล์เดโม — ใช้หาไฟล์ของสคริปต์นี้ตอน --reset/--remove
SOURCE_DEMO = "seed_demo"  # การเข้าร่วมที่สคริปต์สร้าง (ลบทิ้งทั้งแถวได้)
SOURCE_DEMO_ORIGINAL = "seed_demo_original"  # ใบต้นฉบับที่แนบให้การเข้าร่วมเดิม (ลบแค่ไฟล์)
DEMO_SOURCES = (SOURCE_DEMO, SOURCE_DEMO_ORIGINAL)

VARIANT_DUPLICATE = "duplicate"
VARIANT_ORDER = (VARIANT_FULL, VARIANT_NO_NAME, VARIANT_LOW_QUALITY, VARIANT_DUPLICATE)

DEFAULT_COUNT = 24
DEFAULT_SEED = 20260914
MIN_COUNT = 4  # น้อยกว่านี้ได้ไม่ครบทุกแบบ


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
    duplicate = max(1, round(count * 0.15))
    low_quality = max(1, round(count * 0.15))
    no_name = max(1, round(count * 0.2))
    full = count - duplicate - low_quality - no_name
    return (
        [VARIANT_FULL] * full
        + [VARIANT_NO_NAME] * no_name
        + [VARIANT_LOW_QUALITY] * low_quality
        + [VARIANT_DUPLICATE] * duplicate
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


def _attach_file(
    session: Session,
    storage: ObjectStorage,
    participation: Participation,
    image_bytes: bytes,
    *,
    reference: str,
    source: str,
    uploaded_by: Optional[int],
    ingested_at: datetime,
) -> RawFile:
    """เขียนไฟล์ลง Bronze ตามโครง path เดียวกับการอัปโหลดจริง"""
    bucket = settings.minio_bucket_bronze
    object_key = (
        f"evidence/year={ingested_at:%Y}/month={ingested_at:%m}"
        f"/activity_id={participation.activity_id}"
        f"/participation_id={participation.id}"
        f"/{uuid.uuid4().hex}_certificate.png"
    )
    storage.upload_object(bucket, object_key, image_bytes, "image/png")
    raw_file = RawFile(
        bucket=bucket,
        object_key=object_key,
        original_filename=f"certificate_{reference}.png",
        content_type="image/png",
        size_bytes=len(image_bytes),
        checksum=hashlib.sha256(image_bytes).hexdigest(),
        source_system=source,
        uploaded_by=uploaded_by,
        ingested_at=ingested_at,
        participation_id=participation.id,
    )
    session.add(raw_file)
    return raw_file


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
    for variant in (v for v in variants if v != VARIANT_DUPLICATE):
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
        image = render_certificate(
            student_name=student.full_name,
            activity_name=activity.name,
            activity_date=activity.start_at,
            category_path=_category_label(session, activity),
            reference=reference,
            variant=variant,
            font_path=font_path,
        )
        _attach_file(
            session, storage, participation, image,
            reference=reference, source=SOURCE_DEMO,
            uploaded_by=user_by_student.get(student.id), ingested_at=upload_time(activity),
        )
        demo.append((variant, participation))

    # --- ไฟล์ซ้ำ: เพื่อนเอาใบของเจ้าของที่อนุมัติไปแล้วมาส่งเป็นของตัวเอง ---
    needed = variants.count(VARIANT_DUPLICATE)
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
        _attach_file(
            session, storage, participation, image,  # bytes เดียวกันเป๊ะ → checksum ตรง
            reference=reference, source=SOURCE_DEMO,
            uploaded_by=user_by_student.get(borrower.id),
            ingested_at=upload_time(activity, extra_hours=12),
        )
        demo.append((VARIANT_DUPLICATE, participation))
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
