"""สคริปต์ใส่ข้อมูลสมมุติ: user 3 role, นิสิต ~20 คน, กิจกรรม ~10 รายการ, การเข้าร่วม ~50 แถว

รัน: python seed.py
"""
import base64
import hashlib
import random
import sys
import uuid
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

# A tiny valid 1x1 PNG used as placeholder evidence so seeded approved/rejected
# participations really have a Bronze object (no "approved without evidence").
_PLACEHOLDER_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)

FACULTIES = {
    "วิศวกรรมศาสตร์": ["วิศวกรรมคอมพิวเตอร์", "วิศวกรรมไฟฟ้า", "วิศวกรรมโยธา"],
    "วิทยาศาสตร์": ["วิทยาการคอมพิวเตอร์", "เคมี", "ชีววิทยา"],
    "ศิลปศาสตร์": ["ภาษาอังกฤษ", "ภาษาไทย"],
    "บริหารธุรกิจ": ["การตลาด", "การเงิน", "การจัดการ"],
}

FIRST_NAMES = [
    "สมชาย", "สมหญิง", "วิชัย", "วิภา", "ประยุทธ", "นิภา", "อนุชา", "ศิริพร",
    "ธนกร", "กัญญา", "ชัยวัฒน์", "พรทิพย์", "ธีรพงษ์", "อรุณี", "สุรชัย", "มาลี",
    "ปิยะ", "รัตนา", "เอกชัย", "จันทร์เพ็ญ",
]
LAST_NAMES = [
    "ใจดี", "รักเรียน", "สุขสันต์", "ทองคำ", "แสงจันทร์", "ศรีสุข", "บุญมี",
    "พงษ์ไพร", "วงศ์ษา", "ชูเกียรติ",
]

LOCATIONS = ["หอประชุมใหญ่", "ห้อง SC101", "สนามกีฬากลาง", "ลานกิจกรรม", "ห้องประชุมคณะ"]

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

# กิจกรรมสมมุติ: ชื่อ / ประเภท / กิจกรรมย่อย(หมวดชั่วโมง) / จำนวนชั่วโมง — ให้สอดคล้องกันตามความหมายจริง (F1)
# (name, activity_type, subcategory_name, hours)
ACTIVITY_DEFS = [
    ("ปฐมนิเทศนิสิตใหม่", "อบรม/สัมมนา",
     "กิจกรรมเตรียมความพร้อมก่อนการใช้ชีวิตในมหาวิทยาลัย (ปฐมนิเทศ)", 4),
    ("กีฬาสีมหาวิทยาลัย", "กีฬา", "กิจกรรมเสริมสร้างคุณค่าแห่งตน", 4),
    ("ค่ายอาสาพัฒนาชนบท", "จิตอาสา",
     "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 6),
    ("อบรมทักษะดิจิทัล", "อบรม/สัมมนา", "กิจกรรมเรียนรู้และรู้เท่าทันเทคโนโลยีดิจิทัล", 4),
    ("งานวันวิทยาศาสตร์", "วิชาการ", "กิจกรรม ICT กับการรู้สารสนเทศ 1", 2),
    ("แข่งขันตอบปัญหาวิชาการ", "วิชาการ", "กิจกรรม ICT กับการรู้สารสนเทศ 2", 2),
    ("จิตอาสาบริจาคโลหิต", "จิตอาสา",
     "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม", 3),
    ("เทศกาลศิลปวัฒนธรรมอาเซียน", "ศิลปวัฒนธรรม", "กิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน", 6),
    ("สัมมนาเตรียมความพร้อมสู่การทำงาน", "อบรม/สัมมนา",
     "กิจกรรมเตรียมความก่อนการใช้ชีวิตนอกมหาวิทยาลัย (ปัจฉิมนิเทศ)", 4),
    ("ค่ายอนุรักษ์สิ่งแวดล้อม", "จิตอาสา", "กิจกรรมบูรณาการ 4", 4),
]


def seed() -> None:
    create_db_and_tables()

    with Session(engine) as session:
        if session.exec(select(User)).first():
            print("มีข้อมูลอยู่แล้ว ข้ามการ seed")
            return

        # --- students (~20) ---
        students = []
        for i in range(1, 21):
            faculty = random.choice(list(FACULTIES.keys()))
            major = random.choice(FACULTIES[faculty])
            student = Student(
                student_id=f"6501{i:04d}",
                full_name=f"{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}",
                faculty=faculty,
                major=major,
                year_level=random.randint(1, 4),
                status=StudentStatus.active,
            )
            students.append(student)
        session.add_all(students)

        session.commit()
        for obj in students:
            session.refresh(obj)

        # --- users (3 role); "student" is linked to the first seeded student ---
        admin_user = User(username="admin", hashed_password=hash_password("admin123"), role=UserRole.admin)
        staff_user = User(username="staff", hashed_password=hash_password("staff123"), role=UserRole.staff)
        student_user = User(
            username="student",
            hashed_password=hash_password("student123"),
            role=UserRole.student,
            student_id=students[0].id,
        )
        users = [admin_user, staff_user, student_user]
        session.add_all(users)
        session.commit()
        for user in users:
            session.refresh(user)

        # --- hour categories/subcategories (เกณฑ์ชั่วโมงกิจกรรม) ---
        subcategory_id_by_name: dict[str, int] = {}
        for category_name, category_hours, subs in HOUR_STRUCTURE:
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

        # --- activities: ownership alternates staff/admin so ownership filtering is testable (F3) ---
        activities = []
        base_date = datetime(2026, 7, 1)
        for i, (name, activity_type, sub_name, hours) in enumerate(ACTIVITY_DEFS):
            owner_is_admin = i % 2 == 1  # alternate owners
            owner_id = admin_user.id if owner_is_admin else staff_user.id
            # admin-owned auto-approve; keep a couple of staff-owned pending for the approval demo
            is_pending = (not owner_is_admin) and i < 4
            activity = Activity(
                name=name,
                activity_type=activity_type,
                is_required=random.choice([True, False]),
                max_participants=random.choice([30, 50, 100, 150]),
                start_at=base_date + timedelta(days=i * 3),
                location=random.choice(LOCATIONS),
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

        activity_by_id = {a.id: a for a in activities}
        approved_activities = [a for a in activities if a.approval_status == ApprovalStatus.approved]

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

        # --- participations (~50), guaranteeing a spread for the linked "student" user ---
        participations = []
        seen_pairs = set()
        demo_statuses = [EvidenceStatus.approved, EvidenceStatus.pending, EvidenceStatus.rejected]
        for activity, status in zip(approved_activities[:3], demo_statuses):
            participations.append(make_participation(students[0].id, activity, status))
            seen_pairs.add((students[0].id, activity.id))

        while len(participations) < 50:
            student = random.choice(students)
            activity = random.choice(activities)
            pair = (student.id, activity.id)
            if pair in seen_pairs:
                continue
            seen_pairs.add(pair)

            evidence_status = random.choices(
                [EvidenceStatus.pending, EvidenceStatus.approved, EvidenceStatus.rejected],
                weights=[3, 6, 1],
            )[0]
            participations.append(make_participation(student.id, activity, evidence_status))
        session.add_all(participations)
        session.commit()
        for p in participations:
            session.refresh(p)

        # --- Bronze evidence: every approved/rejected participation must have a real file (F2);
        #     plus ~half of the pending ones (uploaded, awaiting review) ---
        storage = get_storage()
        bucket = settings.minio_bucket_bronze
        try:
            storage.ensure_bucket(bucket)
        except Exception as exc:  # noqa: BLE001
            print(f"เตือน: เชื่อม MinIO ไม่ได้ ({exc}) — บันทึก raw_file แต่ไม่อัปโหลดไฟล์จริง")
            storage = None

        checksum = hashlib.sha256(_PLACEHOLDER_PNG).hexdigest()
        raw_files = []
        for p in participations:
            needs_evidence = p.evidence_status in (
                EvidenceStatus.approved,
                EvidenceStatus.rejected,
            ) or (p.evidence_status == EvidenceStatus.pending and random.random() < 0.5)
            if not needs_evidence:
                continue
            now = datetime.utcnow()
            object_key = (
                f"evidence/year={now:%Y}/month={now:%m}"
                f"/activity_id={p.activity_id}/participation_id={p.id}"
                f"/{uuid.uuid4().hex}_seed.png"
            )
            if storage is not None:
                storage.upload_object(bucket, object_key, _PLACEHOLDER_PNG, "image/png")
            raw_files.append(
                RawFile(
                    bucket=bucket,
                    object_key=object_key,
                    original_filename="seed_evidence.png",
                    content_type="image/png",
                    size_bytes=len(_PLACEHOLDER_PNG),
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
            f"seed สำเร็จ: users={len(users)}, students={len(students)}, "
            f"activities={len(activities)}, participations={len(participations)}, "
            f"raw_files={len(raw_files)} "
            f"(user 'student' → student_id={students[0].id}, รหัสนิสิต {students[0].student_id})"
        )


if __name__ == "__main__":
    seed()
