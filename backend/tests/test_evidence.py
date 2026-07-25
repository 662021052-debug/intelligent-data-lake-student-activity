"""Phase 8 (Bronze raw_file metadata) + Phase 9 (evidence upload/view)."""
import hashlib
import re
from datetime import datetime

from sqlmodel import select

from app.auth import hash_password
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    Participation,
    RawFile,
    Student,
    StudentStatus,
    User,
    UserRole,
)

PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"fake-png-body-for-tests"


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _register_staff(client, tokens, username):
    client.post(
        "/auth/register",
        json={"username": username, "password": "pw123456", "role": "staff"},
        headers=_admin_headers(tokens),
    )
    login = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def _make_student_user(session, client, username, student_id_str):
    student = Student(
        student_id=student_id_str,
        full_name="นิสิตหลักฐาน",
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)

    user = User(
        username=username,
        hashed_password=hash_password("pw123456"),
        role=UserRole.student,
        student_id=student.id,
    )
    session.add(user)
    session.commit()
    login = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return student, {"Authorization": f"Bearer {login.json()['access_token']}"}


def _make_activity(session, created_by, name="กิจกรรมหลักฐาน"):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=False,
        max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง SC101",
        created_by=created_by,
        approval_status=ApprovalStatus.approved,
        approved_by=created_by,
        approved_at=datetime.utcnow(),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _make_participation(session, student_id, activity_id, status=EvidenceStatus.pending):
    participation = Participation(
        student_id=student_id, activity_id=activity_id, evidence_status=status
    )
    session.add(participation)
    session.commit()
    session.refresh(participation)
    return participation


# ---------------- Phase 9: upload permissions & validation ----------------

def test_student_uploads_own_evidence_lands_in_storage(client, session, storage):
    student, headers = _make_student_user(session, client, "ev_owner", "8301001")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)

    response = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("proof.png", PNG_BYTES, "image/png")},
        headers=headers,
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["has_evidence"] is True
    assert body["evidence_uploaded_at"] is not None
    assert body["evidence_status"] == "pending"

    raw_file = session.exec(
        select(RawFile).where(RawFile.participation_id == participation.id)
    ).first()
    assert raw_file is not None
    # file really stored in the (in-memory) bronze bucket
    assert storage.get_object_bytes(raw_file.bucket, raw_file.object_key) == PNG_BYTES


def test_student_cannot_upload_for_other_participation(client, session):
    owner, _ = _make_student_user(session, client, "ev_a", "8301010")
    _, other_headers = _make_student_user(session, client, "ev_b", "8301011")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, owner.id, activity.id)

    response = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("proof.png", PNG_BYTES, "image/png")},
        headers=other_headers,
    )
    assert response.status_code == 403


def test_upload_unsupported_type_rejected(client, session):
    student, headers = _make_student_user(session, client, "ev_type", "8301020")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)

    response = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("malware.exe", b"MZ\x90\x00", "application/x-msdownload")},
        headers=headers,
    )
    assert response.status_code == 400


def test_upload_over_10mb_rejected(client, session):
    student, headers = _make_student_user(session, client, "ev_big", "8301030")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)

    too_big = b"0" * (10 * 1024 * 1024 + 1)
    response = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("huge.png", too_big, "image/png")},
        headers=headers,
    )
    assert response.status_code == 413


def test_reupload_allowed_after_rejected(client, session):
    # B2: a rejected participation must accept a fresh upload so the student can fix it
    student, headers = _make_student_user(session, client, "ev_rej", "8301045")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(
        session, student.id, activity.id, status=EvidenceStatus.rejected
    )

    response = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("fix.png", PNG_BYTES, "image/png")},
        headers=headers,
    )
    assert response.status_code == 201
    assert response.json()["evidence_status"] == "pending"  # back into the review queue


def test_evidence_content_type_matches_pdf(client, session):
    # B1: the stream must carry the real Content-Type, not JSON / octet-stream
    student, headers = _make_student_user(session, client, "ev_pdf", "8301046")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)
    client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("doc.pdf", b"%PDF-1.4 hello", "application/pdf")},
        headers=headers,
    )

    response = client.get(f"/participations/{participation.id}/evidence")  # staff owner
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/pdf")
    assert response.content == b"%PDF-1.4 hello"


def test_upload_after_approved_rejected(client, session):
    student, headers = _make_student_user(session, client, "ev_approved", "8301040")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(
        session, student.id, activity.id, status=EvidenceStatus.approved
    )

    response = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("proof.png", PNG_BYTES, "image/png")},
        headers=headers,
    )
    assert response.status_code == 400


def test_reupload_allowed_while_pending(client, session):
    student, headers = _make_student_user(session, client, "ev_re", "8301050")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)

    first = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("first.png", PNG_BYTES, "image/png")},
        headers=headers,
    )
    assert first.status_code == 201
    second = client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("second.pdf", b"%PDF-1.4 second", "application/pdf")},
        headers=headers,
    )
    assert second.status_code == 201

    # Bronze is immutable: both uploads are preserved as separate objects.
    rows = session.exec(
        select(RawFile).where(RawFile.participation_id == participation.id)
    ).all()
    assert len(rows) == 2


# ---------------- Phase 9: viewing evidence ----------------

def test_staff_owner_can_view_evidence(client, session):
    student, student_headers = _make_student_user(session, client, "ev_view", "8301060")
    activity = _make_activity(session, _staff_id(session))  # owned by default staff
    participation = _make_participation(session, student.id, activity.id)
    client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("proof.png", PNG_BYTES, "image/png")},
        headers=student_headers,
    )

    response = client.get(f"/participations/{participation.id}/evidence")  # default = staff owner
    assert response.status_code == 200
    assert response.content == PNG_BYTES
    assert response.headers["content-type"].startswith("image/png")


def test_other_staff_cannot_view_evidence(client, session, tokens):
    student, student_headers = _make_student_user(session, client, "ev_view2", "8301070")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)
    client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("proof.png", PNG_BYTES, "image/png")},
        headers=student_headers,
    )

    other_staff_headers = _register_staff(client, tokens, "ev_reviewer2")
    response = client.get(
        f"/participations/{participation.id}/evidence", headers=other_staff_headers
    )
    assert response.status_code == 403


def test_view_evidence_none_uploaded_returns_404(client, session):
    student, _ = _make_student_user(session, client, "ev_none", "8301080")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)

    response = client.get(f"/participations/{participation.id}/evidence")  # staff owner
    assert response.status_code == 404


# ---------------- Phase 8: Bronze raw_file metadata / data lineage ----------------

def test_raw_file_metadata_is_complete_and_correct(client, session):
    student, headers = _make_student_user(session, client, "ev_meta", "8301090")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)

    client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("หลักฐาน.png", PNG_BYTES, "image/png")},
        headers=headers,
    )

    raw_file = session.exec(
        select(RawFile).where(RawFile.participation_id == participation.id)
    ).first()
    assert raw_file is not None
    assert raw_file.bucket == "bronze"
    assert raw_file.original_filename == "หลักฐาน.png"
    assert raw_file.content_type == "image/png"
    assert raw_file.size_bytes == len(PNG_BYTES)
    assert raw_file.checksum == hashlib.sha256(PNG_BYTES).hexdigest()
    assert raw_file.source_system == "student_upload"
    assert raw_file.uploaded_by is not None
    assert raw_file.ingested_at is not None


def test_raw_file_object_key_follows_bronze_path_layout(client, session):
    student, headers = _make_student_user(session, client, "ev_key", "8301100")
    activity = _make_activity(session, _staff_id(session))
    participation = _make_participation(session, student.id, activity.id)

    client.post(
        f"/participations/{participation.id}/evidence",
        files={"file": ("proof.png", PNG_BYTES, "image/png")},
        headers=headers,
    )

    raw_file = session.exec(
        select(RawFile).where(RawFile.participation_id == participation.id)
    ).first()
    pattern = (
        r"^evidence/year=\d{4}/month=\d{2}"
        rf"/activity_id={activity.id}/participation_id={participation.id}/[0-9a-f]{{32}}_.+$"
    )
    assert re.match(pattern, raw_file.object_key), raw_file.object_key
