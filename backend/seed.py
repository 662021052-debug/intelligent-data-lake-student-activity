"""สคริปต์ใส่ข้อมูลสมมุติ: user 3 role, นิสิต ~20 คน, กิจกรรม ~10 รายการ, การเข้าร่วม ~50 แถว

รัน: python seed.py
"""
import random
import sys
from datetime import datetime, timedelta

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlmodel import Session, select

from app.auth import hash_password
from app.database import create_db_and_tables, engine
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    Student,
    StudentStatus,
    User,
    UserRole,
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

ACTIVITY_TYPES = ["จิตอาสา", "กีฬา", "วิชาการ", "ศิลปวัฒนธรรม", "อบรม/สัมมนา"]
HOUR_CATEGORIES = ["บังคับ", "เลือกเสรี", "จิตอาสา"]
LOCATIONS = ["หอประชุมใหญ่", "ห้อง SC101", "สนามกีฬากลาง", "ลานกิจกรรม", "ห้องประชุมคณะ"]

ACTIVITY_NAMES = [
    "ปฐมนิเทศนิสิตใหม่", "กีฬาสีมหาวิทยาลัย", "ค่ายอาสาพัฒนาชนบท",
    "อบรมทักษะดิจิทัล", "งานวันวิทยาศาสตร์", "แข่งขันตอบปัญหาวิชาการ",
    "จิตอาสาบริจาคโลหิต", "เทศกาลศิลปวัฒนธรรม", "สัมมนาเตรียมความพร้อมสู่การทำงาน",
    "ค่ายอนุรักษ์สิ่งแวดล้อม",
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

# จับคู่กิจกรรมสมมุติแต่ละอันเข้ากับกิจกรรมย่อยที่ใกล้เคียงที่สุด (เพื่อ demo หน้าชั่วโมงสะสม)
ACTIVITY_SUBCATEGORY_MAP = {
    "ปฐมนิเทศนิสิตใหม่": "กิจกรรมเตรียมความพร้อมก่อนการใช้ชีวิตในมหาวิทยาลัย (ปฐมนิเทศ)",
    "กีฬาสีมหาวิทยาลัย": "กิจกรรมเสริมสร้างคุณค่าแห่งตน",
    "ค่ายอาสาพัฒนาชนบท": "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม",
    "อบรมทักษะดิจิทัล": "กิจกรรมเรียนรู้และรู้เท่าทันเทคโนโลยีดิจิทัล",
    "งานวันวิทยาศาสตร์": "กิจกรรม ICT กับการรู้สารสนเทศ 1",
    "แข่งขันตอบปัญหาวิชาการ": "กิจกรรม ICT กับการรู้สารสนเทศ 2",
    "จิตอาสาบริจาคโลหิต": "กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม",
    "เทศกาลศิลปวัฒนธรรม": "กิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน",
    "สัมมนาเตรียมความพร้อมสู่การทำงาน": "กิจกรรมเตรียมความก่อนการใช้ชีวิตนอกมหาวิทยาลัย (ปัจฉิมนิเทศ)",
    "ค่ายอนุรักษ์สิ่งแวดล้อม": "กิจกรรมบูรณาการ 4",
}


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

        # --- activities (~10), owned by staff; most already approved by admin ---
        activities = []
        base_date = datetime(2026, 7, 1)
        for i, name in enumerate(ACTIVITY_NAMES):
            is_pending = i < 2  # a couple left pending so the approval workflow has something to demo
            activity = Activity(
                name=name,
                activity_type=random.choice(ACTIVITY_TYPES),
                hour_category=random.choice(HOUR_CATEGORIES),
                is_required=random.choice([True, False]),
                max_participants=random.choice([30, 50, 100, 150]),
                start_at=base_date + timedelta(days=i * 3),
                location=random.choice(LOCATIONS),
                subcategory_id=subcategory_id_by_name[ACTIVITY_SUBCATEGORY_MAP[name]],
                created_by=staff_user.id,
                approval_status=ApprovalStatus.pending if is_pending else ApprovalStatus.approved,
                approved_by=None if is_pending else admin_user.id,
                approved_at=None if is_pending else base_date,
            )
            activities.append(activity)
        session.add_all(activities)

        session.commit()
        for obj in activities:
            session.refresh(obj)

        # --- participations (~50), guaranteeing a few for the linked "student" user ---
        participations = []
        seen_pairs = set()
        for activity in activities[:3]:
            evidence_status = random.choice(
                [EvidenceStatus.pending, EvidenceStatus.approved, EvidenceStatus.rejected]
            )
            checked_in = evidence_status != EvidenceStatus.pending
            participations.append(
                Participation(
                    student_id=students[0].id,
                    activity_id=activity.id,
                    check_in_time=activity.start_at if checked_in else None,
                    hours_earned=round(random.uniform(1, 6), 1) if checked_in else 0,
                    evidence_status=evidence_status,
                )
            )
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
            checked_in = evidence_status != EvidenceStatus.pending
            participations.append(
                Participation(
                    student_id=student.id,
                    activity_id=activity.id,
                    check_in_time=activity.start_at if checked_in else None,
                    hours_earned=round(random.uniform(1, 6), 1) if checked_in else 0,
                    evidence_status=evidence_status,
                )
            )
        session.add_all(participations)

        session.commit()

        print(
            f"seed สำเร็จ: users={len(users)}, students={len(students)}, "
            f"activities={len(activities)}, participations={len(participations)} "
            f"(user 'student' → student_id={students[0].id}, รหัสนิสิต {students[0].student_id})"
        )


if __name__ == "__main__":
    seed()
