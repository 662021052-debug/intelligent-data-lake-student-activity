"""ดาวน์โหลดข้อมูลดิบของ Bronze / Silver — เฉพาะ admin

- Bronze = ไฟล์หลักฐานต้นฉบับใน MinIO (`raw_file`) → ไฟล์เดียว หรือ ZIP หลายไฟล์
- Silver = ผล OCR (`silver_evidence_ocr`) → CSV

ข้อมูลชุดนี้มีชื่อ/รหัสนิสิตและเอกสารส่วนตัว จึงจำกัดที่ `require_admin` (staff ก็ 403)

**ทุกอย่างเป็น stream**: ฐานข้อมูลถูกอ่านทีละชุด (keyset ตาม id) และไฟล์ใน MinIO ถูกดึงทีละ
chunk เข้า ZIP ที่ประกอบแบบไม่ต้องย้อนกลับ (data descriptor) — หน่วยความจำจึงเท่ากับ
"ไฟล์ใหญ่สุด 1 chunk + แถวหนึ่งชุด" ไม่ว่าจะมีหลักฐานกี่พันไฟล์

generator ของ StreamingResponse ต้องเปิด Session เอง ไม่ใช้ Session จาก `Depends(get_session)`:
FastAPI รุ่นที่ใช้อยู่ปิด dependency แบบ yield ก่อนเริ่มส่ง body
"""

import csv
import io
import re
import zipfile
from datetime import date, datetime, time, timedelta
from enum import Enum
from typing import Callable, Iterator, Optional
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlmodel import Session, select

from app.auth import require_admin
from app.database import get_session
from app.models import Participation, RawFile, SilverEvidenceOcr
from app.storage import ObjectStorage, get_storage

router = APIRouter(prefix="/export", tags=["export"], dependencies=[Depends(require_admin)])

BATCH_SIZE = 200
CSV_MEDIA_TYPE = "text/csv; charset=utf-8"
ZIP_MEDIA_TYPE = "application/zip"
MISSING_FILES_NAME = "_MISSING_FILES.txt"


# ---------------------------------------------------------------- helpers
def _attachment_headers(filename: str, ascii_fallback: str) -> dict[str, str]:
    """Content-Disposition ที่พาชื่อไฟล์ภาษาไทยไปได้ (`filename*` RFC 5987 + fallback ASCII)"""
    return {
        "Content-Disposition": (
            f'attachment; filename="{ascii_fallback}"; filename*=UTF-8\'\'{quote(filename)}'
        )
    }


def _ascii_fallback(filename: str, default: str) -> str:
    """ชื่อ ASCII ล้วนสำหรับ `filename=` — ตัวที่ไม่ใช่ ASCII/อักขระต้องห้ามใน header เปลี่ยนเป็น _"""
    ext = filename[filename.rfind(".") :] if "." in filename else ""
    ext = re.sub(r"[^A-Za-z0-9.]", "", ext)
    return default + ext


def _safe_name(name: str) -> str:
    """ชื่อไฟล์เดิมที่ปลอดภัยใช้เป็นชื่อใน ZIP — ตัด path ทิ้ง (กัน zip-slip `../`) และอักขระควบคุม
    แต่คงภาษาไทยไว้"""
    base = name.replace("\\", "/").split("/")[-1].strip()
    base = re.sub(r'[\x00-\x1f\x7f"<>:|?*]', "_", base)
    return base[:150] or "file"


def _date_range(
    date_from: Optional[date], date_to: Optional[date]
) -> tuple[Optional[datetime], Optional[datetime]]:
    """ช่วงวันที่แบบรวมทั้งวันปลาย เป็น [start, end) — ตัวเวลาในฐานข้อมูลเป็น UTC"""
    if date_from and date_to and date_from > date_to:
        raise HTTPException(status_code=422, detail="date_from ต้องไม่หลัง date_to")
    start = datetime.combine(date_from, time.min) if date_from else None
    end = datetime.combine(date_to + timedelta(days=1), time.min) if date_to else None
    return start, end


def _keyset_batches(bind, model, apply_filters: Callable) -> Iterator[list]:
    """อ่านแถวของ `model` ทีละ BATCH_SIZE เรียงตาม id ด้วย Session ของตัวเอง

    ใช้ keyset (`id > last`) ไม่ใช่ OFFSET เพื่อให้ตารางที่กำลังมีแถวเข้ามายังอ่านได้ครบ
    และไม่ช้าลงเมื่ออ่านลึก · Session ปิดทุกชุด จึงไม่ถือ connection ค้างระหว่างที่ client
    กำลังดาวน์โหลดช้า ๆ
    """
    last_id = 0
    while True:
        with Session(bind) as session:
            stmt = apply_filters(select(model)).where(model.id > last_id)
            rows = session.exec(stmt.order_by(model.id).limit(BATCH_SIZE)).all()
            session.expunge_all()
        if not rows:
            return
        yield rows
        last_id = rows[-1].id


def _filtered(
    stmt,
    model,
    time_column,
    activity_id: Optional[int],
    student_id: Optional[int],
    start: Optional[datetime],
    end: Optional[datetime],
):
    """ตัวกรองร่วมของ Bronze/Silver — activity/student ผ่านตาราง participation"""
    if activity_id is not None or student_id is not None:
        stmt = stmt.join(Participation, Participation.id == model.participation_id)
        if activity_id is not None:
            stmt = stmt.where(Participation.activity_id == activity_id)
        if student_id is not None:
            stmt = stmt.where(Participation.student_id == student_id)
    if start is not None:
        stmt = stmt.where(time_column >= start)
    if end is not None:
        stmt = stmt.where(time_column < end)
    return stmt


# ---------------------------------------------------------------- Bronze: one file
@router.get("/bronze/{raw_file_id}")
def export_bronze_file(
    raw_file_id: int,
    session: Session = Depends(get_session),
    storage: ObjectStorage = Depends(get_storage),
):
    raw_file = session.get(RawFile, raw_file_id)
    if not raw_file:
        raise HTTPException(status_code=404, detail="ไม่พบไฟล์หลักฐาน")
    try:
        chunks = storage.iter_object(raw_file.bucket, raw_file.object_key)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="ไม่พบไฟล์ในที่จัดเก็บ")

    filename = _safe_name(raw_file.original_filename)
    headers = _attachment_headers(filename, _ascii_fallback(filename, f"bronze-{raw_file.id}"))
    return StreamingResponse(chunks, media_type=raw_file.content_type, headers=headers)


# ---------------------------------------------------------------- Bronze: ZIP
class _ZipSink(io.RawIOBase):
    """ปลายทางของ ZipFile ที่ไม่เก็บอะไรไว้ — สะสมไบต์ที่เพิ่งเขียนไว้ให้ generator ดึงไปส่งต่อ

    มี `tell()` แต่ `seek()` ใช้ไม่ได้ ZipFile จึงเข้าโหมด non-seekable ที่เขียน data
    descriptor ต่อท้ายแต่ละไฟล์แทนการย้อนกลับมาแก้ header
    """

    def __init__(self) -> None:
        self._buf = bytearray()
        self._pos = 0

    def writable(self) -> bool:
        return True

    def write(self, data) -> int:
        self._buf += data
        self._pos += len(data)
        return len(data)

    def tell(self) -> int:
        return self._pos

    def drain(self) -> bytes:
        out = bytes(self._buf)
        self._buf.clear()
        return out


def _zip_stream(bind, storage: ObjectStorage, apply_filters: Callable) -> Iterator[bytes]:
    sink = _ZipSink()
    missing: list[str] = []
    with zipfile.ZipFile(sink, "w", zipfile.ZIP_STORED, allowZip64=True) as zf:
        for batch in _keyset_batches(bind, RawFile, apply_filters):
            for raw_file in batch:
                # ชื่อไม่ชนกันเพราะขึ้นต้นด้วย id — ไฟล์ชื่อเดิมซ้ำกันของคนละคนอยู่ร่วมกันได้
                name = f"{raw_file.id}_{_safe_name(raw_file.original_filename)}"
                try:
                    chunks = storage.iter_object(raw_file.bucket, raw_file.object_key)
                except FileNotFoundError:
                    # ไม่ให้ไฟล์เดียวที่หายทำ ZIP ทั้งก้อนพัง (ส่งไปแล้วครึ่งทาง เปลี่ยน status ไม่ได้)
                    missing.append(f"{raw_file.id}\t{raw_file.bucket}/{raw_file.object_key}")
                    continue
                info = zipfile.ZipInfo(name, date_time=raw_file.ingested_at.timetuple()[:6])
                info.compress_type = zipfile.ZIP_STORED  # jpg/png/pdf บีบไม่ลงแล้ว — ไม่เสีย CPU
                with zf.open(info, "w", force_zip64=True) as entry:
                    for chunk in chunks:
                        entry.write(chunk)
                        yield sink.drain()
                yield sink.drain()
        if missing:
            body = "ไฟล์ต่อไปนี้มีแถวใน raw_file แต่ไม่พบใน MinIO:\n" + "\n".join(missing) + "\n"
            zf.writestr(MISSING_FILES_NAME, body.encode("utf-8"))
    yield sink.drain()  # central directory


@router.get("/bronze.zip")
def export_bronze_zip(
    activity_id: Optional[int] = None,
    student_id: Optional[int] = None,
    date_from: Optional[date] = Query(None, description="ingested_at ตั้งแต่วันนี้ (UTC, รวมวันนี้)"),
    date_to: Optional[date] = Query(None, description="ingested_at ถึงวันนี้ (UTC, รวมวันนี้)"),
    session: Session = Depends(get_session),
    storage: ObjectStorage = Depends(get_storage),
):
    start, end = _date_range(date_from, date_to)

    def apply_filters(stmt):
        return _filtered(stmt, RawFile, RawFile.ingested_at, activity_id, student_id, start, end)

    # ตอบ 404 ตอนนี้เลย — เริ่ม stream แล้วเปลี่ยน status ไม่ได้ และ ZIP ว่างเปิดไม่ขึ้นในบางโปรแกรม
    if session.exec(apply_filters(select(RawFile.id)).limit(1)).first() is None:
        raise HTTPException(status_code=404, detail="ไม่พบไฟล์หลักฐานตามเงื่อนไขที่เลือก")

    filename = f"bronze_evidence_{datetime.utcnow():%Y-%m-%d}.zip"
    return StreamingResponse(
        _zip_stream(session.get_bind(), storage, apply_filters),
        media_type=ZIP_MEDIA_TYPE,
        headers=_attachment_headers(filename, filename),
    )


# ---------------------------------------------------------------- Silver: CSV
# ข้อความ OCR มาจากไฟล์ที่นิสิตอัปโหลด (ไม่น่าเชื่อถือ) — เซลล์ที่ขึ้นต้นด้วยอักขระเหล่านี้
# Excel จะตีความเป็นสูตรได้ (CSV injection) จึงนำหน้าด้วย ' ให้เป็นข้อความเฉย ๆ
_FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")


def _csv_cell(value):
    if value is None:
        return ""
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str) and value.startswith(_FORMULA_PREFIXES):
        return "'" + value
    return value


def _silver_csv_stream(bind, apply_filters: Callable) -> Iterator[bytes]:
    columns = [c.name for c in SilverEvidenceOcr.__table__.columns]
    buf = io.StringIO()
    writer = csv.writer(buf)

    def flush() -> bytes:
        data = buf.getvalue().encode("utf-8")
        buf.seek(0)
        buf.truncate()
        return data

    yield b"\xef\xbb\xbf"  # UTF-8 BOM — ไม่มี Excel จะอ่านภาษาไทยเป็นตัวเพี้ยน
    writer.writerow(columns)
    yield flush()
    for batch in _keyset_batches(bind, SilverEvidenceOcr, apply_filters):
        for row in batch:
            writer.writerow([_csv_cell(getattr(row, name)) for name in columns])
        yield flush()


@router.get("/silver.csv")
def export_silver_csv(
    activity_id: Optional[int] = None,
    student_id: Optional[int] = None,
    date_from: Optional[date] = Query(None, description="processed_at ตั้งแต่วันนี้ (UTC, รวมวันนี้)"),
    date_to: Optional[date] = Query(None, description="processed_at ถึงวันนี้ (UTC, รวมวันนี้)"),
    session: Session = Depends(get_session),
):
    start, end = _date_range(date_from, date_to)

    def apply_filters(stmt):
        return _filtered(
            stmt, SilverEvidenceOcr, SilverEvidenceOcr.processed_at, activity_id, student_id, start, end
        )

    filename = f"silver_evidence_ocr_{datetime.utcnow():%Y-%m-%d}.csv"
    return StreamingResponse(
        _silver_csv_stream(session.get_bind(), apply_filters),
        media_type=CSV_MEDIA_TYPE,
        headers=_attachment_headers(filename, filename),
    )
