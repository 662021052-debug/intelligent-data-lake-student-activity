"""Phase 14 — the upload -> background OCR wiring, exercised for real.

conftest globally stubs silver.process_evidence_in_background so unrelated upload
tests don't touch dev.db. Here we (a) prove the upload endpoint actually schedules
it, and (b) run the real function end-to-end against an isolated engine.
"""

import base64
from datetime import datetime

from sqlmodel import Session as SQLSession
from sqlmodel import SQLModel, create_engine, select
from sqlmodel.pool import StaticPool

from app import silver

# Capture the REAL function at import time — before conftest's autouse fixture
# replaces the module attribute with a no-op.
from app.silver import process_evidence_in_background as real_background

from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    OcrDecision,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
    StudentStatus,
    User,
)
from app.storage import InMemoryStorage

# 1x1 PNG
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)


class FakeOcr:
    def __init__(self, text, confidence):
        self.text = text
        self.confidence = confidence

    def run_ocr(self, image_bytes: bytes):
        return (self.text, self.confidence)


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def test_upload_schedules_background_ocr(client, session, storage, tokens, monkeypatch):
    """POST /evidence enqueues the background OCR task with the right id."""
    calls: list[int] = []
    monkeypatch.setattr(silver, "process_evidence_in_background", lambda pid: calls.append(pid))

    student = Student(
        student_id="79001", full_name="นายทดสอบ อัปโหลด", faculty="วิศวกรรมศาสตร์",
        major="คอมพิวเตอร์", year_level=2, status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)
    activity = Activity(
        name="ค่าย", activity_type="จิตอาสา", is_required=False, max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0), location="ห้อง", hours=4,
        created_by=_staff_id(session), approval_status=ApprovalStatus.approved,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    p = Participation(student_id=student.id, activity_id=activity.id,
                      evidence_status=EvidenceStatus.pending, hours_earned=0)
    session.add(p)
    session.commit()
    session.refresh(p)

    resp = client.post(
        f"/participations/{p.id}/evidence",
        data={"evidence_kind": "certificate"}, files={"file": ("proof.png", PNG, "image/png")},
        headers=_admin_headers(tokens),
    )
    assert resp.status_code == 201, resp.text
    assert calls == [p.id]  # background task was scheduled with this participation


def test_background_function_processes_and_auto_approves(monkeypatch):
    """The real process_evidence_in_background opens its own engine session,
    resolves get_ocr/get_storage, and auto-approves a clearly-matching file."""
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    fake_storage = InMemoryStorage()

    with SQLSession(engine) as s:
        student = Student(
            student_id="79002", full_name="นางสาวจริงใจ ตรงเป๊ะ", faculty="วิทยาศาสตร์",
            major="เคมี", year_level=1, status=StudentStatus.active,
        )
        s.add(student)
        s.commit()
        s.refresh(student)
        activity = Activity(
            name="อบรมจริยธรรม", activity_type="อบรม", is_required=False, max_participants=40,
            start_at=datetime(2026, 8, 1, 9, 0, 0), location="ห้อง", hours=5,
            created_by=None, approval_status=ApprovalStatus.approved,
        )
        s.add(activity)
        s.commit()
        s.refresh(activity)
        p = Participation(student_id=student.id, activity_id=activity.id,
                          evidence_status=EvidenceStatus.pending, hours_earned=0)
        s.add(p)
        s.commit()
        s.refresh(p)
        object_key = f"evidence/test/p={p.id}/proof.png"
        fake_storage.upload_object("bronze", object_key, PNG, "image/png")
        s.add(RawFile(
            bucket="bronze", object_key=object_key, original_filename="proof.png",
            content_type="image/png", size_bytes=len(PNG), checksum="bg" + "0" * 62,
            source_system="student_upload", participation_id=p.id,
        ))
        s.commit()
        pid = p.id
        buddhist_year = activity.start_at.year + 543
        matching_text = f"{student.full_name} เข้าร่วม {activity.name} ปี {buddhist_year}"

    # The background function imports engine / get_ocr / get_storage at call time.
    monkeypatch.setattr("app.database.engine", engine)
    monkeypatch.setattr("app.ocr.get_ocr", lambda: FakeOcr(matching_text, 0.95))
    monkeypatch.setattr("app.storage.get_storage", lambda: fake_storage)

    real_background(pid)

    with SQLSession(engine) as s:
        row = s.exec(
            select(SilverEvidenceOcr).where(SilverEvidenceOcr.participation_id == pid)
        ).first()
        assert row is not None
        assert row.decision == OcrDecision.auto_approved
        updated = s.get(Participation, pid)
        assert updated.evidence_status == EvidenceStatus.approved
        assert updated.hours_earned == 5
