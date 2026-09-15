"""OCR เฟส 3B — PDF: render หน้าเป็นภาพด้วย PyMuPDF แล้ว OCR เหมือนไฟล์ภาพ

OCR เป็นตัวปลอมเสมอ (ไม่เรียก EasyOCR จริงในเทส) · PDF สร้างจริงด้วย PyMuPDF
"""
import io
from datetime import datetime

import pymupdf
import pytest
from PIL import Image, ImageDraw

from app.config import settings
from app.fonts import find_thai_font
from app.models import (
    Activity,
    EvidenceStatus,
    OcrDecision,
    Participation,
    RawFile,
    Student,
    StudentStatus,
)
from app.pdf import extract_text_layer, render_pdf_pages
from app.phash import compute_phash, phash_distance
from app.silver import process_participation_evidence

STUDENT_NAME = "นายสมชาย ใจดี"
ACTIVITY_NAME = "ค่ายอาสาพัฒนาชนบท"
# ข้อความที่ OCR "อ่านได้" จากเกียรติบัตรที่ตรงกับนิสิต/กิจกรรม (ปี พ.ศ. 2569 = ค.ศ. 2026)
MATCHING_TEXT = f"เกียรติบัตร {STUDENT_NAME} ได้เข้าร่วมกิจกรรม {ACTIVITY_NAME} วันที่ 1 สิงหาคม 2569"


class SequenceOcr:
    """OCR ปลอมที่คืนผลตามลำดับการเรียก และจำไบต์ที่ได้รับไว้ตรวจ"""

    def __init__(self, results):
        self.results = list(results)
        self.received: list[bytes] = []

    def run_ocr(self, image_bytes: bytes):
        self.received.append(image_bytes)
        return self.results[len(self.received) - 1]


class FailingOcr:
    calls = 0

    def run_ocr(self, image_bytes: bytes):
        self.calls += 1
        raise RuntimeError("OCR ไม่ควรถูกเรียก")


def _png(shade: int = 0, size=(800, 560)) -> bytes:
    img = Image.new("RGB", size, "white")
    draw = ImageDraw.Draw(img)
    draw.rectangle((20, 20, size[0] - 20, size[1] - 20), outline=(30, 60, 140), width=12)
    draw.ellipse((80, 120, 360, 400), fill=(200, shade, 40))
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def _pdf(pages: int = 1, page_size=(595, 842)) -> bytes:
    """PDF จริง [pages] หน้า แต่ละหน้ามีภาพหนึ่งภาพเต็มหน้า"""
    doc = pymupdf.open()
    for i in range(pages):
        page = doc.new_page(width=page_size[0], height=page_size[1])
        page.insert_image(page.rect, stream=_png(shade=i * 40))
    data = doc.tobytes()
    doc.close()
    return data


def _participation_with_file(session, storage, data: bytes, content_type="application/pdf") -> Participation:
    student = Student(
        student_id="87001", full_name=STUDENT_NAME, faculty="วิศวกรรมศาสตร์",
        major="คอมพิวเตอร์", year_level=2, status=StudentStatus.active,
    )
    activity = Activity(
        name=ACTIVITY_NAME, activity_type="จิตอาสา", is_required=False, max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0), location="ห้อง", hours=4,
    )
    session.add(student)
    session.add(activity)
    session.commit()
    p = Participation(student_id=student.id, activity_id=activity.id,
                      evidence_status=EvidenceStatus.pending, hours_earned=0)
    session.add(p)
    session.commit()
    session.refresh(p)
    key = f"evidence/test/p={p.id}/proof.pdf"
    storage.upload_object("bronze", key, data, content_type)
    session.add(RawFile(
        bucket="bronze", object_key=key, original_filename="proof.pdf", content_type=content_type,
        size_bytes=len(data), checksum=f"pdf{p.id}".ljust(64, "0"), source_system="student_upload",
        participation_id=p.id,
    ))
    session.commit()
    return p


# ------------------------------ render ------------------------------


def test_render_returns_one_png_per_page_up_to_the_limit():
    pages = render_pdf_pages(_pdf(pages=5), max_pages=3, dpi=200, max_side_px=4000)

    assert len(pages) == 3
    for page in pages:
        assert page.startswith(b"\x89PNG")
        with Image.open(io.BytesIO(page)) as img:
            # A4 595x842 pt ที่ 200 DPI ≈ 1653x2339 พิกเซล
            assert abs(img.width - 595 * 200 / 72) <= 2 and abs(img.height - 842 * 200 / 72) <= 2


def test_render_caps_the_longest_side_of_oversized_pages():
    """หน้าขนาด 5000 pt (≈ 1.76 เมตร) ที่ 200 DPI จะเป็นภาพ ~13,900 พิกเซล — ต้องถูกจำกัดไว้"""
    pages = render_pdf_pages(_pdf(pages=1, page_size=(5000, 5000)), max_pages=1, dpi=200, max_side_px=4000)

    with Image.open(io.BytesIO(pages[0])) as img:
        assert max(img.size) <= 4000


def test_render_raises_on_a_broken_pdf():
    with pytest.raises(Exception):
        render_pdf_pages(b"%PDF-1.4\n%not really", max_pages=3, dpi=200, max_side_px=4000)


# ------------------------------ pipeline ------------------------------


def test_pdf_with_matching_text_is_ocrd_and_scored_like_an_image(session, storage):
    """PDF ที่ข้อความตรงกับนิสิต/กิจกรรม → ได้คะแนนตรงเหมือนภาพ ไม่เด้ง needs_review อัตโนมัติ"""
    p = _participation_with_file(session, storage, _pdf(pages=1))
    ocr = SequenceOcr([(MATCHING_TEXT, 0.9)])

    row = process_participation_evidence(session, ocr, storage, p.id)

    assert len(ocr.received) == 1 and ocr.received[0].startswith(b"\x89PNG"), "ส่งภาพ PNG ของหน้าเข้า OCR"
    assert row.extracted_text == MATCHING_TEXT
    assert row.ocr_confidence == 0.9
    assert row.match_score >= settings.ocr_auto_match
    assert row.decision == OcrDecision.auto_approved
    assert session.get(Participation, p.id).evidence_status == EvidenceStatus.approved


def test_multi_page_pdf_joins_readable_pages_and_averages_their_confidence(session, storage):
    p = _participation_with_file(session, storage, _pdf(pages=5))
    ocr = SequenceOcr([("หน้าแรก", 0.8), ("   ", 0.0), ("หน้าสาม", 0.6)])

    row = process_participation_evidence(session, ocr, storage, p.id)

    assert len(ocr.received) == settings.ocr_pdf_max_pages == 3, "อ่านแค่ 3 หน้าแรกจาก 5"
    assert row.extracted_text == "หน้าแรก\nหน้าสาม"
    assert row.ocr_confidence == pytest.approx(0.7), "หน้าว่างไม่ดึงค่าเฉลี่ยลง"


def test_pdf_page_limit_comes_from_config(session, storage, monkeypatch):
    monkeypatch.setattr(settings, "ocr_pdf_max_pages", 1)
    p = _participation_with_file(session, storage, _pdf(pages=4))
    ocr = SequenceOcr([("หน้าเดียว", 0.7)])

    process_participation_evidence(session, ocr, storage, p.id)

    assert len(ocr.received) == 1


def test_pdf_with_no_readable_page_needs_review(session, storage):
    p = _participation_with_file(session, storage, _pdf(pages=2))

    row = process_participation_evidence(session, SequenceOcr([("", 0.0), ("", 0.0)]), storage, p.id)

    assert (row.extracted_text, row.ocr_confidence, row.decision) == ("", 0.0, OcrDecision.needs_review)


def test_broken_pdf_needs_review_and_never_reaches_ocr(session, storage):
    p = _participation_with_file(session, storage, b"%PDF-1.4\n%truncated garbage")
    ocr = FailingOcr()

    row = process_participation_evidence(session, ocr, storage, p.id)

    assert ocr.calls == 0
    assert (row.extracted_text, row.ocr_confidence, row.decision) == ("", 0.0, OcrDecision.needs_review)


# ------------------------------ pHash ของ PDF ------------------------------


def test_pdf_first_page_phash_is_near_the_same_image_sent_as_jpeg():
    """ใบเดียวกันส่งแบบ PDF กับ JPG → pHash ใกล้กัน (เข้าเกณฑ์ภาพคล้ายของเฟส 3A.2)"""
    image = Image.open(io.BytesIO(_png()))
    doc = pymupdf.open()
    page = doc.new_page(width=image.width, height=image.height)
    page.insert_image(page.rect, stream=_png())
    pdf = doc.tobytes()
    doc.close()
    jpeg = io.BytesIO()
    image.convert("RGB").save(jpeg, "JPEG", quality=80)

    from_pdf = compute_phash(pdf, "application/pdf")
    from_jpeg = compute_phash(jpeg.getvalue(), "image/jpeg")

    assert from_pdf is not None and from_jpeg is not None
    assert phash_distance(from_pdf, from_jpeg) <= settings.ocr_phash_near_bits


# ------------------ text layer ก่อน OCR (PDF ที่ export จากโปรแกรม) ------------------

THAI_FONT = find_thai_font()
needs_thai_font = pytest.mark.skipif(
    THAI_FONT is None, reason="ไม่มีฟอนต์ไทยในเครื่อง — ฝังข้อความไทยลง PDF ไม่ได้"
)
CERT_LINES = [
    "มหาวิทยาลัยทักษิณ",
    "เกียรติบัตรฉบับนี้ให้ไว้เพื่อแสดงว่า",
    STUDENT_NAME,
    "ได้เข้าร่วมกิจกรรม",
    ACTIVITY_NAME,
    "จัดขึ้นเมื่อวันที่ 1 สิงหาคม 2569",
]


def _text_pdf(lines, pages: int = 1) -> bytes:
    """PDF ที่มีข้อความไทยแบบ vector (text layer) — แบบเกียรติบัตรที่ export จากโปรแกรม"""
    doc = pymupdf.open()
    for _ in range(pages):
        page = doc.new_page(width=842, height=595)
        y = 100
        for line in lines:
            page.insert_text((60, y), line, fontsize=22, fontname="thai", fontfile=THAI_FONT)
            y += 50
    data = doc.tobytes()
    doc.close()
    return data


@needs_thai_font
def test_extract_text_layer_reads_vector_text_and_is_empty_for_image_only_pdf():
    layer = extract_text_layer(_text_pdf(CERT_LINES), max_pages=3)

    assert STUDENT_NAME in layer and ACTIVITY_NAME in layer
    assert extract_text_layer(_pdf(pages=2), max_pages=3) == "", "PDF ภาพล้วนไม่มี text layer"


@needs_thai_font
def test_pdf_with_text_layer_skips_ocr_and_uses_the_layer(session, storage):
    p = _participation_with_file(session, storage, _text_pdf(CERT_LINES))
    ocr = FailingOcr()

    row = process_participation_evidence(session, ocr, storage, p.id)

    assert ocr.calls == 0, "มี text layer ต้องไม่เรียก OCR"
    assert STUDENT_NAME in row.extracted_text and ACTIVITY_NAME in row.extracted_text
    assert row.ocr_confidence == settings.ocr_pdf_text_layer_confidence
    assert row.match_score >= settings.ocr_auto_match
    assert row.decision == OcrDecision.auto_approved


def test_image_only_pdf_falls_back_to_render_and_ocr(session, storage):
    """PDF สแกน (ภาพล้วน ไม่มี text layer) → render + OCR เหมือนเดิม"""
    p = _participation_with_file(session, storage, _pdf(pages=1))
    ocr = SequenceOcr([(MATCHING_TEXT, 0.8)])

    row = process_participation_evidence(session, ocr, storage, p.id)

    assert len(ocr.received) == 1
    assert (row.extracted_text, row.ocr_confidence) == (MATCHING_TEXT, 0.8)


@needs_thai_font
def test_too_little_text_layer_falls_back_to_ocr(session, storage):
    """มีข้อความแค่เลขหน้า (น้อยกว่าเกณฑ์) ไม่นับเป็น text layer → render + OCR"""
    p = _participation_with_file(session, storage, _text_pdf(["หน้า 1"]))
    ocr = SequenceOcr([(MATCHING_TEXT, 0.8)])

    row = process_participation_evidence(session, ocr, storage, p.id)

    assert len(ocr.received) == 1
    assert row.extracted_text == MATCHING_TEXT


@needs_thai_font
def test_text_layer_threshold_comes_from_config(session, storage, monkeypatch):
    monkeypatch.setattr(settings, "ocr_pdf_text_layer_min_chars", 10_000)  # ไม่มีใบไหนผ่าน → OCR เสมอ
    p = _participation_with_file(session, storage, _text_pdf(CERT_LINES))
    ocr = SequenceOcr([(MATCHING_TEXT, 0.8)])

    process_participation_evidence(session, ocr, storage, p.id)

    assert len(ocr.received) == 1


@needs_thai_font
def test_text_layer_pdf_still_gets_phash_from_its_rendered_page():
    phash = compute_phash(_text_pdf(CERT_LINES), "application/pdf")

    assert phash is not None and len(phash) == 64
