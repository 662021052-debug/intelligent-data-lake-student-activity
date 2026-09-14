"""หลักฐานเดโมของหน้าตรวจหลักฐาน — ไฟล์จริงใน Bronze + ผล OCR คละ decision

OCR เป็นตัวปลอม (ไม่เรียกโมเดลจริง) ที่ "อ่านเจอ" ชื่อนิสิต/กิจกรรมทุกคน เพื่อทดสอบว่าเส้นทาง
auto_approved เกิดได้ ส่วน flagged ต้องเกิดจาก checksum ซ้ำเสมอไม่ว่า OCR จะอ่านได้อะไร
"""

from collections import Counter
from datetime import datetime, timedelta

import pytest
from sqlmodel import func, select

from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    ImportedCompletion,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
    StudentStatus,
    User,
)
from seed_evidence_demo import (
    SOURCE_DEMO,
    SOURCE_DEMO_ORIGINAL,
    VARIANT_DUPLICATE,
    SeedAborted,
    plan_variants,
    populate,
    remove_demo,
)

NOW = datetime(2026, 9, 14, 12, 0)


class ReadsEverythingOcr:
    """OCR ปลอมที่คืนข้อความมีชื่อทุกคน + ทุกกิจกรรม + ปี พ.ศ. ด้วยความมั่นใจสูง"""

    def __init__(self, text: str):
        self.text = text

    def run_ocr(self, image_bytes: bytes):
        return (self.text, 0.9)


class BlindOcr:
    def run_ocr(self, image_bytes: bytes):
        return ("", 0.0)


@pytest.fixture
def world(session):
    staff_id = session.exec(select(User).where(User.username == "staff")).one().id
    students = []
    for i in range(40):
        students.append(
            Student(
                student_id=f"69{i:07d}",
                full_name=f"นายทดสอบ นามสกุล{i}",
                faculty="คณะทดสอบ",
                major="ไม่ระบุ",
                year_level=1,
                status=StudentStatus.active,
                imported_completion=ImportedCompletion.failed if i == 0 else ImportedCompletion.passed,
            )
        )
    session.add_all(students)
    activities = []
    for i in range(6):
        activities.append(
            Activity(
                name=f"กิจกรรมทดสอบลำดับที่{i}",
                activity_type="จิตอาสา",
                is_required=False,
                max_participants=30,
                start_at=NOW - timedelta(days=10 + i * 2),
                location="หอประชุม",
                hours=3,
                created_by=staff_id,
                approval_status=ApprovalStatus.approved,
            )
        )
    # กิจกรรมที่ยังไม่จัด ห้ามถูกเลือก
    activities.append(
        Activity(
            name="กิจกรรมอนาคต", activity_type="จิตอาสา", is_required=False, max_participants=30,
            start_at=NOW + timedelta(days=5), location="หอประชุม", hours=3,
            created_by=staff_id, approval_status=ApprovalStatus.approved,
        )
    )
    session.add_all(activities)
    session.commit()
    # การเข้าร่วมที่อนุมัติแล้ว (แบบเฟส 5) ให้เป็นใบต้นฉบับของเคสไฟล์ซ้ำ
    for student in students[1:11]:
        session.add(
            Participation(
                student_id=student.id, activity_id=activities[0].id,
                check_in_time=activities[0].start_at, hours_earned=3,
                evidence_status=EvidenceStatus.approved,
            )
        )
    session.commit()
    text = " ".join(
        [s.full_name for s in students] + [a.name for a in activities] + [str(NOW.year + 543)]
    )
    return {"students": students, "activities": activities, "text": text}


def _decisions(session):
    rows = session.exec(select(SilverEvidenceOcr)).all()
    return Counter(r.decision.value if hasattr(r.decision, "value") else r.decision for r in rows)


def test_plan_has_every_variant():
    plan = Counter(plan_variants(24))
    assert sum(plan.values()) == 24
    assert set(plan) == {"full", "no_name", "low_quality", VARIANT_DUPLICATE}
    with pytest.raises(SeedAborted):
        plan_variants(3)


def test_every_demo_participation_has_file_and_ocr_with_mixed_decisions(session, storage, world):
    report = populate(session, storage, ReadsEverythingOcr(world["text"]), now=NOW, count=12, log=lambda _: None)

    demo_files = session.exec(select(RawFile).where(RawFile.source_system == SOURCE_DEMO)).all()
    assert len(demo_files) == 12 == report.participations
    for raw_file in demo_files:
        # ไฟล์อยู่ใน storage จริง และ OCR มีผลของไฟล์นั้น
        assert storage.get_object_bytes(raw_file.bucket, raw_file.object_key)
        assert session.exec(
            select(SilverEvidenceOcr).where(SilverEvidenceOcr.raw_file_id == raw_file.id)
        ).first()

    decisions = _decisions(session)
    duplicates = plan_variants(12).count(VARIANT_DUPLICATE)
    assert decisions["flagged"] == duplicates
    assert decisions["auto_approved"] > 0
    assert sum(decisions.values()) == 12


def test_flagged_is_guaranteed_even_when_ocr_reads_nothing(session, storage, world):
    populate(session, storage, BlindOcr(), now=NOW, count=8, log=lambda _: None)
    decisions = _decisions(session)
    assert decisions["flagged"] == plan_variants(8).count(VARIANT_DUPLICATE)
    assert decisions["needs_review"] == 8 - decisions["flagged"]
    assert decisions["auto_approved"] == 0


def test_respects_status_capacity_time_and_past_activities(session, storage, world):
    populate(session, storage, ReadsEverythingOcr(world["text"]), now=NOW, count=12, log=lambda _: None)
    demo_ids = {
        f.participation_id
        for f in session.exec(select(RawFile).where(RawFile.source_system == SOURCE_DEMO)).all()
    }
    demo = [session.get(Participation, pid) for pid in demo_ids]
    failed_student = world["students"][0]
    future = world["activities"][-1]

    assert all(p.student_id != failed_student.id for p in demo), "ห้ามแตะนิสิตที่ไม่ผ่านตามไฟล์"
    assert all(p.activity_id != future.id for p in demo), "ส่งหลักฐานกิจกรรมที่ยังไม่จัดไม่ได้"
    # ไม่มีใครลงกิจกรรมเดียวกันซ้ำ และไม่มีกิจกรรมไหนเกินที่นั่ง
    pairs = session.exec(select(Participation.student_id, Participation.activity_id)).all()
    assert len(pairs) == len(set(pairs))
    for activity in world["activities"]:
        taken = session.exec(
            select(func.count()).select_from(Participation).where(Participation.activity_id == activity.id)
        ).one()
        assert taken <= activity.max_participants


def test_originals_keep_their_hours_and_duplicates_share_checksum(session, storage, world):
    populate(session, storage, BlindOcr(), now=NOW, count=8, log=lambda _: None)
    originals = session.exec(select(RawFile).where(RawFile.source_system == SOURCE_DEMO_ORIGINAL)).all()
    assert originals
    for original in originals:
        owner = session.get(Participation, original.participation_id)
        assert owner.evidence_status == EvidenceStatus.approved
        assert owner.hours_earned == 3
        copies = session.exec(
            select(RawFile).where(RawFile.checksum == original.checksum, RawFile.id != original.id)
        ).all()
        assert len(copies) == 1 and copies[0].source_system == SOURCE_DEMO


def test_rerun_refuses_and_remove_cleans_up_only_demo(session, storage, world):
    before = session.exec(select(func.count()).select_from(Participation)).one()
    populate(session, storage, BlindOcr(), now=NOW, count=8, log=lambda _: None)
    with pytest.raises(SeedAborted):
        populate(session, storage, BlindOcr(), now=NOW, count=8, log=lambda _: None)

    keys = [(f.bucket, f.object_key) for f in session.exec(select(RawFile)).all()]
    removed, files = remove_demo(session, storage)
    session.commit()

    assert removed == 8
    assert files == len(keys)
    assert session.exec(select(func.count()).select_from(Participation)).one() == before
    assert session.exec(select(func.count()).select_from(RawFile)).one() == 0
    assert session.exec(select(func.count()).select_from(SilverEvidenceOcr)).one() == 0
    for bucket, key in keys:
        with pytest.raises(FileNotFoundError):
            storage.get_object_bytes(bucket, key)
    # ต้นฉบับยังอนุมัติอยู่เหมือนเดิม
    approved = session.exec(
        select(func.count()).select_from(Participation).where(Participation.evidence_status == EvidenceStatus.approved)
    ).one()
    assert approved == 10
