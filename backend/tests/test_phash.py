"""OCR เฟส 3A.1 — pHash 256 บิตของไฟล์หลักฐานภาพ: คำนวณตอนอัปโหลด + ทนการบีบอัด/ปรับขนาด

* ภาพสังเคราะห์วาดด้วย Pillow (deterministic ไม่พึ่งอะไรภายนอก)
* เกียรติบัตรจริงวาดด้วย ``render_certificate`` ตัวเดียวกับ seed — ต้องมีฟอนต์ไทย ไม่มีก็ข้าม
  (ไม่มีฟอนต์ไทย ตัวอักษรกลายเป็นกล่อง ภาพไม่สะท้อนของจริง)
"""
import io
from datetime import datetime
from itertools import combinations

import pytest
from PIL import Image, ImageDraw
from sqlmodel import select

from app.fonts import find_thai_font
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    Participation,
    RawFile,
    Student,
    StudentStatus,
    User,
)
from app.phash import PHASH_BITS, PHASH_HEX_LENGTH, compute_phash, phash_distance
from seed_evidence import render_certificate

# threshold เริ่มต้นของเฟส 3A.2 (≤ 16 บิตจาก 256) — วัดบนเกียรติบัตรเดโมจริงแล้ว:
# สำเนาบีบอัด/ย่อ 6–10 บิต · ใบคนละคนเทมเพลตเดียวกันห่างอย่างน้อย 24 บิต
NEAR_BITS = 16

THAI_FONT = find_thai_font()
needs_thai_font = pytest.mark.skipif(
    THAI_FONT is None, reason="ไม่มีฟอนต์ไทยในเครื่อง — เกียรติบัตรจะเป็นกล่องสี่เหลี่ยม"
)


def _certificate_like() -> Image.Image:
    img = Image.new("RGB", (800, 560), "white")
    draw = ImageDraw.Draw(img)
    draw.rectangle((20, 20, 780, 540), outline=(30, 60, 140), width=12)
    draw.ellipse((80, 120, 360, 400), fill=(200, 40, 40))
    for i in range(6):
        draw.rectangle((420, 100 + i * 60, 740, 130 + i * 60), fill=(20 * i, 90, 160))
    return img


def _unrelated() -> Image.Image:
    img = Image.new("RGB", (800, 560), (250, 240, 200))
    draw = ImageDraw.Draw(img)
    for x in range(0, 800, 40):
        draw.line((x, 0, 800 - x, 560), fill=(0, 0, 0), width=8)
    draw.rectangle((500, 300, 760, 520), fill=(10, 120, 40))
    return img


def _encode(img: Image.Image, fmt: str = "PNG", **kwargs) -> bytes:
    buf = io.BytesIO()
    img.save(buf, fmt, **kwargs)
    return buf.getvalue()


def _real_certificate(student: str, activity: str, category: str, day: int, reference: str) -> bytes:
    return render_certificate(
        student_name=student,
        activity_name=activity,
        activity_date=datetime(2026, 8, day),
        category_path=category,
        reference=reference,
        font_path=THAI_FONT,
    )


# ------------------------------ unit ------------------------------


def test_image_gets_a_256_bit_hex_phash_that_is_stable():
    data = _encode(_certificate_like())

    first = compute_phash(data, "image/png")

    assert PHASH_BITS == 256
    assert first is not None and len(first) == PHASH_HEX_LENGTH == 64
    int(first, 16)  # hex ล้วน
    assert compute_phash(data, "image/png") == first
    distance = phash_distance(first, first)
    assert distance == 0 and type(distance) is int, "ต้องเป็น int ธรรมดา ไม่ใช่ numpy.int64"


def test_recompressed_and_resized_copies_stay_near():
    original = _certificate_like()
    base = compute_phash(_encode(original), "image/png")

    recompressed = compute_phash(_encode(original, "JPEG", quality=35), "image/jpeg")
    resized = compute_phash(
        _encode(original.resize((400, 280)), "JPEG", quality=60), "image/jpeg"
    )

    assert phash_distance(base, recompressed) <= NEAR_BITS
    assert phash_distance(base, resized) <= NEAR_BITS


def test_unrelated_image_is_far():
    a = compute_phash(_encode(_certificate_like()), "image/png")
    b = compute_phash(_encode(_unrelated()), "image/png")

    assert phash_distance(a, b) > NEAR_BITS * 2


def test_exif_orientation_is_applied_before_hashing():
    """รูปเดียวกันที่มือถือบันทึกหมุนไว้ + ป้ายทิศทางใน EXIF ต้องได้ hash ใกล้ของตั้งตรง"""
    original = _certificate_like()
    exif = Image.Exif()
    exif[0x0112] = 6  # Orientation: หมุน 90° ตามเข็มนาฬิกาตอนแสดง
    stored_rotated = original.rotate(90, expand=True)  # เก็บไว้แบบหมุนทวนเข็ม 90°

    upright = compute_phash(_encode(original, "JPEG", quality=90), "image/jpeg")
    with_exif = compute_phash(
        _encode(stored_rotated, "JPEG", quality=90, exif=exif.tobytes()), "image/jpeg"
    )
    without_exif = compute_phash(_encode(stored_rotated, "JPEG", quality=90), "image/jpeg")

    assert phash_distance(upright, with_exif) <= NEAR_BITS
    assert phash_distance(upright, without_exif) > NEAR_BITS, "ไม่มี EXIF = ภาพเอียงจริง ต้องห่าง"


def test_broken_pdf_and_undecodable_image_have_no_phash():
    assert compute_phash(b"%PDF-1.4 fake", "application/pdf") is None
    assert compute_phash(b"\x89PNG\r\n\x1a\nnot-really-a-png", "image/png") is None


# ---------------------- เกียรติบัตรจริง (เทมเพลตเดียวกับ seed) ----------------------


@needs_thai_font
def test_real_certificate_recompressed_or_resized_stays_within_threshold():
    png = _real_certificate(
        "นางสาวกรวรรณ ยาง๊ะ", "ตลาดนัดผู้ประกอบการรุ่นเยาว์ ครั้งที่ 5/2569",
        "ด้านการเป็นผู้ประกอบการ", 22, "TSU-180-62162-025853",
    )
    image = Image.open(io.BytesIO(png)).convert("RGB")
    base = compute_phash(png, "image/png")

    jpeg = compute_phash(_encode(image, "JPEG", quality=40), "image/jpeg")
    resized = compute_phash(
        _encode(image.resize((image.width // 2, image.height // 2)), "JPEG", quality=60), "image/jpeg"
    )

    assert phash_distance(base, jpeg) <= NEAR_BITS
    assert phash_distance(base, resized) <= NEAR_BITS


@needs_thai_font
def test_same_template_different_certificates_are_beyond_threshold():
    """ใบฟอร์มเดียวกันคนละคน (รวมกิจกรรมเดียวกัน) ต้องไม่ถูกนับว่า "คล้าย" ด้วย pHash อย่างเดียว

    เหตุผลที่เลือก 256 บิต: ที่ 64 บิตใบเหล่านี้ชนกันเองที่ระยะ ≤ 6
    """
    certificates = [
        ("นางสาวกรวรรณ ยาง๊ะ", "ตลาดนัดผู้ประกอบการรุ่นเยาว์ ครั้งที่ 5/2569",
         "ด้านการเป็นผู้ประกอบการ", 22, "TSU-180-62162-025853"),
        ("นายวัชระ แก้วเทพ", "ตลาดนัดผู้ประกอบการรุ่นเยาว์ ครั้งที่ 5/2569",
         "ด้านการเป็นผู้ประกอบการ", 22, "TSU-180-91469-7A21C0"),
        ("นางสาวนูรีญา อนนตรี", "กีฬาสัมพันธ์ละลายพฤติกรรม ครั้งที่ 1/2569",
         "การทำงานร่วมกับผู้อื่น", 19, "TSU-113-62262-BF947D"),
        ("นายภูวดล สมหวัง", "เวิร์กช็อปสุขภาพจิตดีมีสุข ครั้งที่ 3/2569",
         "การบริหารจัดการตนเอง", 3, "TSU-110-62081-44E1A2"),
    ]
    hashes = [compute_phash(_real_certificate(*c), "image/png") for c in certificates]

    distances = [phash_distance(a, b) for a, b in combinations(hashes, 2)]

    assert min(distances) > NEAR_BITS, distances


# ------------------------------ upload API ------------------------------


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _participation(session):
    staff = session.exec(select(User).where(User.username == "staff")).first()
    student = Student(
        student_id="8501001", full_name="นิสิตพีแฮช", faculty="วิศวกรรมศาสตร์",
        major="คอมพิวเตอร์", year_level=2, status=StudentStatus.active,
    )
    activity = Activity(
        name="กิจกรรมพีแฮช", activity_type="วิชาการ", is_required=False, max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0), location="ห้อง", hours=3,
        created_by=staff.id, approval_status=ApprovalStatus.approved,
    )
    session.add(student)
    session.add(activity)
    session.commit()
    p = Participation(student_id=student.id, activity_id=activity.id, evidence_status=EvidenceStatus.pending)
    session.add(p)
    session.commit()
    session.refresh(p)
    return p


def _upload(client, tokens, participation_id, filename, data, content_type):
    return client.post(
        f"/participations/{participation_id}/evidence",
        files={"file": (filename, data, content_type)},
        data={"evidence_kind": "certificate"},
        headers=_admin_headers(tokens),
    )


def _latest_raw(session, participation_id):
    session.expire_all()
    return session.exec(
        select(RawFile).where(RawFile.participation_id == participation_id).order_by(RawFile.id.desc())
    ).first()


def test_uploaded_image_stores_its_phash(client, session, tokens):
    p = _participation(session)
    data = _encode(_certificate_like(), "JPEG", quality=85)

    assert _upload(client, tokens, p.id, "proof.jpg", data, "image/jpeg").status_code == 201

    raw = _latest_raw(session, p.id)
    assert raw.phash is not None and len(raw.phash) == 64
    assert raw.phash == compute_phash(data, "image/jpeg")


def test_uploaded_broken_pdf_has_no_phash(client, session, tokens):
    p = _participation(session)

    assert _upload(client, tokens, p.id, "proof.pdf", b"%PDF-1.4\n%fake", "application/pdf").status_code == 201

    assert _latest_raw(session, p.id).phash is None


def test_uploaded_pdf_stores_first_page_phash(client, session, tokens):
    """เฟส 3B: PDF ใช้หน้าแรกคำนวณ pHash — ใบเดียวกันที่ส่งแบบ PDF กับ JPG จะเทียบกันได้"""
    import pymupdf

    image = _certificate_like()
    doc = pymupdf.open()
    page = doc.new_page(width=image.width, height=image.height)
    page.insert_image(page.rect, stream=_encode(image))
    pdf = doc.tobytes()
    doc.close()
    p = _participation(session)

    assert _upload(client, tokens, p.id, "proof.pdf", pdf, "application/pdf").status_code == 201

    raw = _latest_raw(session, p.id)
    assert raw.phash is not None and len(raw.phash) == 64
    jpeg = compute_phash(_encode(image, "JPEG", quality=80), "image/jpeg")
    assert phash_distance(raw.phash, jpeg) <= NEAR_BITS


def test_undecodable_image_still_uploads_without_phash(client, session, tokens):
    """ไฟล์ที่อ้างว่าเป็นภาพแต่ถอดไม่ได้ — การอัปโหลดต้องไม่ล้มเพราะ pHash"""
    p = _participation(session)

    response = _upload(client, tokens, p.id, "proof.png", b"\x89PNG\r\n\x1a\nbroken", "image/png")

    assert response.status_code == 201, response.text
    assert _latest_raw(session, p.id).phash is None
