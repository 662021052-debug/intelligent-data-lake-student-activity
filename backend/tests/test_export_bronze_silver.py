"""ดาวน์โหลด Bronze (ไฟล์เดียว/ZIP) และ Silver (CSV) — เฉพาะ admin

ไฟล์ที่ได้ถูกเปิดอ่านกลับจริง (zipfile / csv) และเทสต์หน่วยความจำวัดด้วย tracemalloc
บน generator ตัวจริง ไม่ใช่แค่ดูว่า endpoint ตอบ 200
"""

import csv
import io
import tracemalloc
import zipfile
from datetime import datetime

import pytest
from sqlmodel import select

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
from app.routers import export as export_module

BOM = b"\xef\xbb\xbf"


def _auth(tokens, role):
    return {"Authorization": f"Bearer {tokens[role]}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _student(session, code, name="นิสิตทดสอบ"):
    s = Student(
        student_id=code, full_name=name, faculty="วิศวกรรมศาสตร์",
        major="คอม", year_level=2, status=StudentStatus.active,
    )
    session.add(s)
    session.commit()
    session.refresh(s)
    return s


def _activity(session, name):
    a = Activity(
        name=name, activity_type="วิชาการ", is_required=False, max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0), location="SC101",
        created_by=_staff_id(session), approval_status=ApprovalStatus.approved,
        approved_by=_staff_id(session), approved_at=datetime.utcnow(),
    )
    session.add(a)
    session.commit()
    session.refresh(a)
    return a


def _participation(session, student, activity):
    p = Participation(
        student_id=student.id, activity_id=activity.id, evidence_status=EvidenceStatus.pending
    )
    session.add(p)
    session.commit()
    session.refresh(p)
    return p


def _raw(session, storage, participation, filename, data, ingested_at=None):
    key = f"evidence/test/participation_id={participation.id if participation else 0}/{filename}"
    storage.upload_object("bronze", key, data, "application/octet-stream")
    raw = RawFile(
        bucket="bronze", object_key=key, original_filename=filename,
        content_type="image/png", size_bytes=len(data), checksum="0" * 64,
        source_system="student_upload",
        participation_id=participation.id if participation else None,
        ingested_at=ingested_at or datetime(2026, 8, 5, 10, 0, 0),
    )
    session.add(raw)
    session.commit()
    session.refresh(raw)
    return raw


def _silver(session, raw, participation, text="ข้อความ OCR", **kw):
    row = SilverEvidenceOcr(
        raw_file_id=raw.id, participation_id=participation.id if participation else None,
        extracted_text=text, ocr_confidence=0.91, match_score=0.8,
        decision=OcrDecision.auto_approved, **kw,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def _read_csv(content: bytes):
    assert content.startswith(BOM)
    return list(csv.DictReader(io.StringIO(content[len(BOM):].decode("utf-8"))))


@pytest.fixture(name="world")
def world_fixture(session, storage):
    """นิสิต 2 คน × กิจกรรม 2 อัน — ไฟล์ 3 ไฟล์ (ชื่อซ้ำกัน 2 ไฟล์ คนละคน)"""
    s1, s2 = _student(session, "6800001", "สมชาย ใจดี"), _student(session, "6800002")
    a1, a2 = _activity(session, "กิจกรรม A"), _activity(session, "กิจกรรม B")
    p1, p2, p3 = (
        _participation(session, s1, a1),
        _participation(session, s2, a1),
        _participation(session, s1, a2),
    )
    r1 = _raw(session, storage, p1, "ใบประกาศ.png", b"PNG-ONE", datetime(2026, 8, 5, 10))
    r2 = _raw(session, storage, p2, "ใบประกาศ.png", b"PNG-TWO", datetime(2026, 8, 6, 10))
    r3 = _raw(session, storage, p3, "cert.pdf", b"%PDF-THREE", datetime(2026, 8, 7, 10))
    _silver(session, r1, p1, "ใบประกาศนียบัตร\nสมชาย ใจดี")
    _silver(session, r2, p2)
    _silver(session, r3, p3)
    return dict(s1=s1, s2=s2, a1=a1, a2=a2, p=[p1, p2, p3], r=[r1, r2, r3])


ENDPOINTS = ["/export/bronze.zip", "/export/silver.csv", "/export/bronze/1"]


# ---------------------------------------------------------------- สิทธิ์
@pytest.mark.parametrize("path", ENDPOINTS)
def test_staff_and_student_get_403(client, tokens, world, path):
    assert client.get(path, headers=_auth(tokens, "staff")).status_code == 403
    assert client.get(path, headers=_auth(tokens, "student")).status_code == 403


@pytest.mark.parametrize("path", ENDPOINTS)
def test_no_token_is_401(client, tokens, world, path):
    client.headers.pop("Authorization")
    assert client.get(path).status_code == 401


@pytest.mark.parametrize("path", ENDPOINTS)
def test_admin_gets_200(client, tokens, world, path):
    assert client.get(path, headers=_auth(tokens, "admin")).status_code == 200


# ---------------------------------------------------------------- Bronze ไฟล์เดียว
def test_single_file_returns_bytes_with_original_thai_filename(client, tokens, world):
    raw = world["r"][0]
    res = client.get(f"/export/bronze/{raw.id}", headers=_auth(tokens, "admin"))
    assert res.content == b"PNG-ONE"
    assert res.headers["content-type"] == "image/png"
    disp = res.headers["content-disposition"]
    assert disp.startswith("attachment;")
    assert "filename*=UTF-8''%E0%B9%83%E0%B8%9A" in disp  # ใบประกาศ.png เป็น percent-encoded
    assert f'filename="bronze-{raw.id}.png"' in disp  # fallback ASCII — header ต้องเป็น latin-1


def test_single_file_404_when_row_or_object_missing(client, tokens, world, storage):
    admin = _auth(tokens, "admin")
    assert client.get("/export/bronze/99999", headers=admin).status_code == 404
    raw = world["r"][2]
    storage.remove_object(raw.bucket, raw.object_key)
    assert client.get(f"/export/bronze/{raw.id}", headers=admin).status_code == 404


def test_single_file_strips_path_from_original_filename(client, tokens, session, storage, world):
    raw = _raw(session, storage, world["p"][0], "../../etc/passwd", b"x")
    res = client.get(f"/export/bronze/{raw.id}", headers=_auth(tokens, "admin"))
    assert "filename*=UTF-8''passwd" in res.headers["content-disposition"]


# ---------------------------------------------------------------- Bronze ZIP
def _zip(res):
    assert res.status_code == 200, res.text
    zf = zipfile.ZipFile(io.BytesIO(res.content))
    assert zf.testzip() is None  # CRC ของทุกไฟล์ตรง = ZIP ที่ stream ออกมาไม่พัง
    return zf


def test_zip_contains_every_file_with_unique_names(client, tokens, world):
    res = client.get("/export/bronze.zip", headers=_auth(tokens, "admin"))
    assert res.headers["content-type"] == "application/zip"
    assert "attachment" in res.headers["content-disposition"]
    zf = _zip(res)
    r1, r2, r3 = world["r"]
    # ชื่อเดิมซ้ำ (ใบประกาศ.png ×2) ต้องไม่ชนกัน
    assert sorted(zf.namelist()) == sorted(
        [f"{r1.id}_ใบประกาศ.png", f"{r2.id}_ใบประกาศ.png", f"{r3.id}_cert.pdf"]
    )
    assert zf.read(f"{r1.id}_ใบประกาศ.png") == b"PNG-ONE"
    assert zf.read(f"{r2.id}_ใบประกาศ.png") == b"PNG-TWO"
    assert zf.read(f"{r3.id}_cert.pdf") == b"%PDF-THREE"


@pytest.mark.parametrize(
    "query,expected",
    [
        ("activity_id={a1}", {0, 1}),
        ("student_id={s1}", {0, 2}),
        ("activity_id={a1}&student_id={s1}", {0}),
        ("date_from=2026-08-06", {1, 2}),
        ("date_to=2026-08-06", {0, 1}),  # date_to รวมทั้งวัน (ไฟล์เวลา 10:00 ของวันที่ 6 ต้องอยู่)
        ("date_from=2026-08-06&date_to=2026-08-06", {1}),
    ],
)
def test_zip_filters(client, tokens, world, query, expected):
    q = query.format(a1=world["a1"].id, s1=world["s1"].id)
    zf = _zip(client.get(f"/export/bronze.zip?{q}", headers=_auth(tokens, "admin")))
    want = {f"{world['r'][i].id}_" for i in expected}
    assert {n.split("_", 1)[0] + "_" for n in zf.namelist()} == want


def test_zip_404_when_filter_matches_nothing(client, tokens, world):
    res = client.get("/export/bronze.zip?student_id=99999", headers=_auth(tokens, "admin"))
    assert res.status_code == 404


def test_reversed_date_range_is_422(client, tokens, world):
    res = client.get(
        "/export/silver.csv?date_from=2026-09-01&date_to=2026-08-01", headers=_auth(tokens, "admin")
    )
    assert res.status_code == 422


def test_zip_survives_missing_object_and_lists_it(client, tokens, world, storage):
    lost = world["r"][1]
    storage.remove_object(lost.bucket, lost.object_key)
    zf = _zip(client.get("/export/bronze.zip", headers=_auth(tokens, "admin")))
    names = zf.namelist()
    assert f"{lost.id}_ใบประกาศ.png" not in names
    assert f"{world['r'][0].id}_ใบประกาศ.png" in names
    report = zf.read("_MISSING_FILES.txt").decode("utf-8")
    assert str(lost.id) in report and lost.object_key in report


def test_zip_spans_multiple_db_batches(client, tokens, session, storage, monkeypatch):
    monkeypatch.setattr(export_module, "BATCH_SIZE", 7)
    p = _participation(session, _student(session, "6809999"), _activity(session, "batch"))
    made = [_raw(session, storage, p, f"f{i}.png", f"data-{i}".encode()) for i in range(23)]
    zf = _zip(client.get("/export/bronze.zip", headers=_auth(tokens, "admin")))
    assert len(zf.namelist()) == 23
    for raw in made:
        assert zf.read(f"{raw.id}_{raw.original_filename}") == f"data-{raw.id - made[0].id}".encode()


def test_zip_entry_name_cannot_escape_directory(client, tokens, session, storage, world):
    raw = _raw(session, storage, world["p"][0], "..\\..\\evil.png", b"x")
    zf = _zip(client.get("/export/bronze.zip", headers=_auth(tokens, "admin")))
    assert f"{raw.id}_evil.png" in zf.namelist()
    assert all(".." not in n and "/" not in n and "\\" not in n for n in zf.namelist())


# ---------------------------------------------------------------- Silver CSV
def test_csv_has_bom_all_columns_and_thai_text(client, tokens, world):
    res = client.get("/export/silver.csv", headers=_auth(tokens, "admin"))
    assert res.headers["content-type"].startswith("text/csv")
    assert "attachment" in res.headers["content-disposition"]
    assert res.content.startswith(BOM)
    rows = _read_csv(res.content)
    assert list(rows[0].keys()) == [c.name for c in SilverEvidenceOcr.__table__.columns]
    assert len(rows) == 3
    first = rows[0]
    assert first["extracted_text"] == "ใบประกาศนียบัตร\nสมชาย ใจดี"  # ไทย + ขึ้นบรรทัดใหม่ในเซลล์
    assert first["decision"] == "auto_approved"
    assert first["is_duplicate"] == "false"
    assert first["ocr_confidence"] == "0.91"
    assert first["raw_file_id"] == str(world["r"][0].id)
    assert first["duplicate_reason"] == ""  # null → เซลล์ว่าง


def test_csv_filters(client, tokens, world):
    admin = _auth(tokens, "admin")
    only_a2 = _read_csv(client.get(f"/export/silver.csv?activity_id={world['a2'].id}", headers=admin).content)
    assert [r["participation_id"] for r in only_a2] == [str(world["p"][2].id)]
    only_s2 = _read_csv(client.get(f"/export/silver.csv?student_id={world['s2'].id}", headers=admin).content)
    assert [r["participation_id"] for r in only_s2] == [str(world["p"][1].id)]


def test_csv_empty_result_still_has_header(client, tokens, world):
    res = client.get("/export/silver.csv?student_id=99999", headers=_auth(tokens, "admin"))
    assert res.status_code == 200
    assert _read_csv(res.content) == []
    assert b"raw_file_id" in res.content


@pytest.mark.parametrize("text", ["=HYPERLINK(\"http://evil\")", "+1+1", "-2+3", "@SUM(A1)"])
def test_csv_neutralises_formula_injection(client, tokens, session, storage, world, text):
    _silver(session, world["r"][0], world["p"][0], text)
    rows = _read_csv(client.get("/export/silver.csv", headers=_auth(tokens, "admin")).content)
    assert rows[-1]["extracted_text"] == "'" + text


def test_csv_spans_multiple_db_batches(client, tokens, session, storage, world, monkeypatch):
    monkeypatch.setattr(export_module, "BATCH_SIZE", 4)
    for i in range(10):
        _silver(session, world["r"][0], world["p"][0], f"row-{i}")
    rows = _read_csv(client.get("/export/silver.csv", headers=_auth(tokens, "admin")).content)
    assert len(rows) == 13
    assert [int(r["id"]) for r in rows] == sorted(int(r["id"]) for r in rows)


# ---------------------------------------------------------------- หน่วยความจำ
def _peak_bytes(iterator) -> tuple[int, int]:
    """(ไบต์รวมที่ไหลผ่าน, peak ของหน่วยความจำที่ตัว generator ถือ) ขณะไล่จนหมด"""
    tracemalloc.start()
    try:
        total = sum(len(chunk) for chunk in iterator)
        _, peak = tracemalloc.get_traced_memory()
    finally:
        tracemalloc.stop()
    return total, peak


def test_zip_streaming_does_not_buffer_the_archive(session, storage):
    """40 ไฟล์ × 1 MB = 40 MB — peak ต้องเล็กกว่าก้อนรวมมาก (ไม่ใช่ทั้ง ZIP ค้างในหน่วยความจำ)"""
    p = _participation(session, _student(session, "6808888"), _activity(session, "big"))
    blob = b"\x00\x01" * (512 * 1024)  # 1 MB (ใช้ก้อนเดียวร่วมกัน — ไม่นับเป็นหน่วยความจำของ generator)
    for i in range(40):
        _raw(session, storage, p, f"big{i}.bin", blob)

    def no_filter(stmt):
        return stmt

    total, peak = _peak_bytes(export_module._zip_stream(session.get_bind(), storage, no_filter))
    assert total > 40 * 1024 * 1024
    assert peak < 4 * 1024 * 1024, f"peak {peak / 1e6:.1f} MB — ZIP ถูก buffer ทั้งก้อน?"


def test_csv_streaming_does_not_buffer_the_table(session, storage):
    """6,000 แถว × ~2 KB ข้อความ ≈ 13 MB — peak ต้องผูกกับขนาด 1 ชุด (BATCH_SIZE แถว) ไม่ใช่ทั้งตาราง"""
    p = _participation(session, _student(session, "6807777"), _activity(session, "many"))
    raw = _raw(session, storage, p, "x.png", b"x")
    text = "ก" * 700  # ≈ 2 KB เมื่อเป็น UTF-8
    session.add_all(
        [
            SilverEvidenceOcr(
                raw_file_id=raw.id, participation_id=p.id, extracted_text=text,
                decision=OcrDecision.needs_review,
            )
            for _ in range(6000)
        ]
    )
    session.commit()

    total, peak = _peak_bytes(export_module._silver_csv_stream(session.get_bind(), lambda s: s))
    assert total > 12 * 1024 * 1024
    assert peak < total / 3, f"peak {peak / 1e6:.1f} MB จากทั้งหมด {total / 1e6:.1f} MB"


# ---------------------------------------------------------------- MinIOStorage.iter_object
def test_minio_iter_object_streams_and_releases_connection():
    """ไม่มี MinIO จริงในเทสต์ — ใช้ client ปลอมตรวจว่าอ่านเป็น chunk และคืน connection เสมอ"""
    from app.storage import MinIOStorage

    class FakeResponse:
        closed = released = False

        def stream(self, amt):
            assert amt == 4
            yield b"abcd"
            yield b"ef"

        def close(self):
            self.closed = True

        def release_conn(self):
            self.released = True

    response = FakeResponse()
    storage = MinIOStorage.__new__(MinIOStorage)  # ข้าม __init__ ที่ต้องต่อ MinIO
    storage._client = type("C", (), {"get_object": lambda self, b, k: response})()

    assert b"".join(storage.iter_object("bronze", "k", chunk_size=4)) == b"abcdef"
    assert response.closed and response.released


def test_minio_iter_object_maps_no_such_key_to_file_not_found():
    from minio.error import S3Error

    from app.storage import MinIOStorage

    def get_object(self, bucket, key):
        raise S3Error("NoSuchKey", "missing", "/k", "req", "host", None)

    storage = MinIOStorage.__new__(MinIOStorage)
    storage._client = type("C", (), {"get_object": get_object})()
    with pytest.raises(FileNotFoundError):  # ต้องเกิดทันที ไม่ใช่ตอน next() — ให้ endpoint ตอบ 404 ได้
        storage.iter_object("bronze", "k")
