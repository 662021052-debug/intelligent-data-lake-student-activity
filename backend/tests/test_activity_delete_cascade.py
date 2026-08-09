"""ลบกิจกรรมต้องเก็บกวาดตลอดสาย Bronze → Silver ไม่ให้เหลือแถวกำพร้า

เดิม `delete_activity` ลบแค่ `participation` แล้ว commit — บน Postgres จะล้มด้วย
FK violation ทันทีที่มีใครอัปโหลดหลักฐาน (raw_file/silver_evidence_ocr ยังชี้มาที่
participation อยู่) แล้วโผล่หน้าเว็บเป็น "เชื่อมต่อเซิร์ฟเวอร์ไม่ได้"

เทสต์ชุดนี้เช็ก "แถวหายจริง" ไม่ใช่พึ่ง FK เพราะ SQLite ที่ conftest ใช้ไม่ได้เปิด
`PRAGMA foreign_keys` ไว้ จึงไม่บ่นแม้จะเหลือแถวกำพร้า — ซึ่งเป็นเหตุผลที่บั๊กนี้
รอดเทสต์เดิมมาได้
"""
from datetime import datetime

from sqlmodel import select

from app.auth import hash_password
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
    StudentStatus,
    User,
    UserRole,
)

PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"fake-png-body-for-tests"


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _make_student_user(session, client, username, student_id_str):
    student = Student(
        student_id=student_id_str,
        full_name="นิสิตลบกิจกรรม",
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)

    session.add(
        User(
            username=username,
            hashed_password=hash_password("pw123456"),
            role=UserRole.student,
            student_id=student.id,
        )
    )
    session.commit()
    login = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return student, {"Authorization": f"Bearer {login.json()['access_token']}"}


def _make_activity(session, created_by, name="กิจกรรมที่จะถูกลบ"):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=False,
        max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง SC101",
        hours=3,
        created_by=created_by,
        approval_status=ApprovalStatus.approved,
        approved_by=created_by,
        approved_at=datetime.utcnow(),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _participation_with_evidence(client, session, storage, username, student_code):
    """สร้างกิจกรรม + การเข้าร่วม + หลักฐานที่อัปโหลดแล้ว (มีทั้ง raw_file และ silver)"""
    student, headers = _make_student_user(session, client, username, student_code)
    activity = _make_activity(session, _staff_id(session))
    participation = Participation(
        student_id=student.id,
        activity_id=activity.id,
        evidence_status=EvidenceStatus.pending,
        hours_earned=3,
    )
    session.add(participation)
    session.commit()
    session.refresh(participation)

    upload = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("proof.png", PNG_BYTES, "image/png")},
        headers=headers,
    )
    assert upload.status_code == 201, upload.text

    raw_file = session.exec(
        select(RawFile).where(RawFile.participation_id == participation.id)
    ).first()
    assert raw_file is not None
    # เติมแถว Silver เองเพื่อไม่ต้องพึ่ง OCR จริงตอนเทสต์
    session.add(
        SilverEvidenceOcr(
            raw_file_id=raw_file.id,
            participation_id=participation.id,
            extracted_text="ใบประกาศทดสอบ",
            ocr_confidence=0.8,
            match_score=0.9,
            decision="needs_review",
            is_duplicate=False,
            processed_at=datetime.utcnow(),
        )
    )
    session.commit()
    return activity, participation, raw_file


def test_delete_activity_removes_evidence_chain(client, session, storage):
    activity, participation, raw_file = _participation_with_evidence(
        client, session, storage, "del_owner", "8401001"
    )
    bucket, object_key = raw_file.bucket, raw_file.object_key

    response = client.delete(f"/activities/{activity.id}")
    assert response.status_code == 204, response.text

    assert session.get(Activity, activity.id) is None
    assert session.get(Participation, participation.id) is None
    assert session.exec(
        select(RawFile).where(RawFile.participation_id == participation.id)
    ).first() is None
    assert session.exec(
        select(SilverEvidenceOcr).where(
            SilverEvidenceOcr.participation_id == participation.id
        )
    ).first() is None

    # ไฟล์ใน object storage ต้องถูกลบด้วย ไม่ปล่อยค้างเป็นขยะที่ไม่มีใครอ้างถึง
    try:
        storage.get_object_bytes(bucket, object_key)
        raise AssertionError("ไฟล์หลักฐานยังอยู่ใน storage ทั้งที่ลบกิจกรรมไปแล้ว")
    except FileNotFoundError:
        pass


def test_delete_activity_keeps_other_activities_evidence(client, session, storage):
    """ลบกิจกรรมหนึ่งต้องไม่ลากหลักฐานของกิจกรรมอื่นหายไปด้วย"""
    doomed, _, _ = _participation_with_evidence(client, session, storage, "del_a", "8401010")
    kept_activity, kept_participation, kept_raw = _participation_with_evidence(
        client, session, storage, "del_b", "8401011"
    )

    assert client.delete(f"/activities/{doomed.id}").status_code == 204

    assert session.get(Activity, kept_activity.id) is not None
    assert session.get(Participation, kept_participation.id) is not None
    assert session.exec(
        select(RawFile).where(RawFile.participation_id == kept_participation.id)
    ).first() is not None
    assert storage.get_object_bytes(kept_raw.bucket, kept_raw.object_key) == PNG_BYTES


def test_delete_activity_without_participation_still_works(client, session):
    """เคสง่ายสุดต้องไม่พังจากโค้ดเก็บกวาดที่เพิ่มเข้ามา"""
    activity = _make_activity(session, _staff_id(session), name="กิจกรรมไม่มีคนลง")
    assert client.delete(f"/activities/{activity.id}").status_code == 204
    assert session.get(Activity, activity.id) is None
