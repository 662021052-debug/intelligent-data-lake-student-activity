"""หลักฐานเดโมของหน้าตรวจหลักฐาน — ไฟล์จริงใน Bronze + ผล OCR คละ decision

OCR เป็นตัวปลอม (ไม่เรียกโมเดลจริง):

* ``ReadsEverythingOcr`` — "อ่านเจอ" ชื่อนิสิต/กิจกรรมทุกคนในทุกใบ เพื่อทดสอบว่า auto_approved เกิดได้
* ``BlindOcr`` — อ่านไม่ออกเลย เพื่อทดสอบว่า flagged ไม่ได้มาจาก OCR
* ``CertificateTextOcr`` — อ่านข้อความของใบแต่ละใบ (ต่างกันตามเจ้าของใบ) ใช้ทดสอบ text veto

สองตัวแรกให้ข้อความเหมือนกันทุกใบ / ว่างทุกใบ text veto จึงทำงานไม่ได้ (ใบเคส B ถูก flag)
"""

import hashlib
from collections import Counter
from datetime import datetime, timedelta

import pytest
from sqlmodel import func, select

from app.config import settings
from app.fonts import find_thai_font
from app.models import (
    Activity,
    ApprovalStatus,
    DuplicateReason,
    EvidenceKind,
    EvidenceStatus,
    ImportedCompletion,
    MatchKind,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
    StudentStatus,
    User,
)
from app.phash import phash_distance
from app.silver import text_similarity
from seed_evidence_demo import (
    SOURCE_DEMO,
    SOURCE_DEMO_ORIGINAL,
    VARIANT_DUPLICATE,
    VARIANT_NEAR_DUPLICATE,
    VARIANT_PDF_SCAN,
    VARIANT_PDF_TEXT,
    VARIANT_PHOTO,
    VARIANT_TEMPLATE_BASE,
    VARIANT_TEMPLATE_TWIN,
    SeedAborted,
    plan_variants,
    populate,
    remove_demo,
)

NOW = datetime(2026, 9, 14, 12, 0)
THAI_FONT = find_thai_font()
needs_thai_font = pytest.mark.skipif(THAI_FONT is None, reason="ไม่มีฟอนต์ไทย — เกียรติบัตร/PDF ภาษาไทยไม่สมจริง")


def _flagged_when_ocr_cannot_veto(count):
    """ใบที่ออกแบบให้โดน flag เมื่อ OCR ให้ข้อความเหมือนกันทุกใบ/อ่านไม่ออก

    exact (duplicate) + near copy (near_duplicate) + เคส B (template_twin — veto ไม่ทำงานเพราะข้อความไม่ต่าง)
    """
    plan = plan_variants(count)
    return plan.count(VARIANT_DUPLICATE) + plan.count(VARIANT_NEAR_DUPLICATE) + plan.count(VARIANT_TEMPLATE_TWIN)


def _assert_designed_fixtures_flagged(report, count, *, twin_flagged: bool):
    """เคสที่ออกแบบไว้ต้องโดน/ไม่โดนตามแบบเป๊ะ ๆ ต่อ variant

    จำนวน flagged "รวม" ตรึงไม่ได้เมื่อ OCR veto ไม่ได้ (อ่านไม่ออก/ข้อความเหมือนกันทุกใบ): ใบ low_quality
    ที่เบลอจนตัวอักษรหาย หน้าตาเข้าใกล้ตัวเทมเพลตเอง pHash ของมันกับใบอื่นเทมเพลตเดียวกันแตะ threshold ได้
    (วัดได้ 16 บิตพอดีกับ pdf_scan ใน 5/12 รอบ) — กฎ "อ่านไม่ออก → คง flag" จึง flag เพิ่มแบบ near
    ซึ่งเป็นพฤติกรรมที่ตั้งใจ (กัน false negative) ไม่ใช่ข้อผิดพลาดของ seed
    """
    plan = plan_variants(count)
    assert report.decisions[VARIANT_DUPLICATE]["flagged"] == plan.count(VARIANT_DUPLICATE)
    assert report.decisions[VARIANT_NEAR_DUPLICATE]["flagged"] == 1
    assert report.decisions[VARIANT_TEMPLATE_TWIN]["flagged"] == (1 if twin_flagged else 0)


class ReadsEverythingOcr:
    """OCR ปลอมที่คืนข้อความมีชื่อทุกคน + ทุกกิจกรรม + ปี พ.ศ. ด้วยความมั่นใจสูง"""

    def __init__(self, text: str):
        self.text = text

    def run_ocr(self, image_bytes: bytes):
        return (self.text, 0.9)


class BlindOcr:
    def run_ocr(self, image_bytes: bytes):
        return ("", 0.0)


class CertificateTextOcr:
    """OCR ปลอมที่ "อ่าน" ข้อความของเกียรติบัตรแต่ละใบได้ (ต่างกันตามเจ้าของใบ)

    หาใบจาก checksum ของไบต์ที่ส่งมา (ใบที่ checksum ซ้ำได้ข้อความของใบแรกสุด = เจ้าของตัวจริง)
    ภาพที่ไม่ใช่ไฟล์ใน Bronze ตรง ๆ (เช่นหน้า PDF ที่ render) อ่านไม่ออก
    """

    def __init__(self, session):
        self.session = session

    def run_ocr(self, image_bytes: bytes):
        checksum = hashlib.sha256(image_bytes).hexdigest()
        raw = self.session.exec(
            select(RawFile).where(RawFile.checksum == checksum).order_by(RawFile.id)
        ).first()
        if raw is None:
            return ("", 0.0)
        participation = self.session.get(Participation, raw.participation_id)
        student = self.session.get(Student, participation.student_id)
        activity = self.session.get(Activity, participation.activity_id)
        text = f"{student.full_name} รหัส {student.student_id} {activity.name} {activity.activity_type}"
        return (text, 0.9)


# ชื่อ/กิจกรรมต้องหลากหลายเหมือนข้อมูลจริง — เกียรติบัตรที่ต่างกันแค่ตัวเลข ("นามสกุล1" กับ "นามสกุล2")
# หน้าตาเกือบเหมือนกันจน pHash ห่างแค่ 2 บิต (27–32 คู่ ≤16 บิต) ชั้นภาพเกือบเหมือนจะ flag ผิดทั้งโลกทดสอบ
# ส่วนชื่อ/กิจกรรมหลากหลายวัดได้คู่ใกล้สุด 26 บิต (ของจริงบนเดโม 24)
_FIRST_NAMES = [
    "สมชาย", "กรวรรณ", "วัชระ", "นูรีญา", "ภูวดล", "ธนกฤต", "ณัฐธิดา", "อรุณี", "ซูลฟาน", "พิมพ์ชนก",
    "กิตติพงษ์", "ศศิธร", "ปิยะพงศ์", "มัลลิกา", "อัครเดช", "เบญจมาศ", "ธีรภัทร", "ฮาฟีซา", "วรเมธ", "จิราพร",
]
_LAST_NAMES = [
    "ใจดี", "ยาง๊ะ", "แก้วเทพ", "อนนตรี", "สมหวัง", "บำขุน", "เสนาะ", "ปะดุกา", "ดือราแม", "ขนุนนิล",
    "ทองสุข", "วงศ์ใหญ่", "ศรีสวัสดิ์", "หมัดหลี", "บุญประเสริฐ", "เพชรรัตน์", "สุวรรณโณ", "มะลิวัลย์", "จันทร์หอม", "แสงอรุณ",
]
_ACTIVITIES = [
    ("ค่ายอาสาพัฒนาชนบท", "จิตอาสา"),
    ("ตลาดนัดผู้ประกอบการรุ่นเยาว์ ครั้งที่ 5/2569", "ผู้ประกอบการ"),
    ("กีฬาสัมพันธ์ละลายพฤติกรรม", "กีฬาและนันทนาการ"),
    ("เวิร์กช็อปสุขภาพจิตดีมีสุข ครั้งที่ 3/2569", "พัฒนาตนเอง"),
    ("รู้เท่าทันสื่อดิจิทัลและ AI", "วิชาการ"),
    ("TSU English Camp ครั้งที่ 1/2569", "ทักษะภาษา"),
]


def _full_name(i: int) -> str:
    prefix = "นาย" if i % 2 == 0 else "นางสาว"
    return f"{prefix}{_FIRST_NAMES[i % 20]} {_LAST_NAMES[(i + (i // 20) * 7) % 20]}"


@pytest.fixture
def world(session):
    staff_id = session.exec(select(User).where(User.username == "staff")).one().id
    students = []
    for i in range(40):
        students.append(
            Student(
                student_id=f"69{i:07d}",
                full_name=_full_name(i),
                faculty="คณะทดสอบ",
                major="ไม่ระบุ",
                year_level=1,
                status=StudentStatus.active,
                imported_completion=ImportedCompletion.failed if i == 0 else ImportedCompletion.passed,
            )
        )
    assert len({s.full_name for s in students}) == 40, "ชื่อซ้ำกันจะทำให้เกียรติบัตรเหมือนกัน"
    session.add_all(students)
    activities = []
    for i, (activity_name, activity_type) in enumerate(_ACTIVITIES):
        activities.append(
            Activity(
                name=activity_name,
                activity_type=activity_type,
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


def _raw_by_marker(session, marker: str) -> RawFile:
    """ไฟล์ของคู่เคส B — เลขอ้างอิงในชื่อไฟล์มี -TB (base) / -TT (twin)"""
    return session.exec(select(RawFile).where(RawFile.original_filename.contains(f"-{marker}"))).one()


def _latest_ocr(session, raw_file_id: int) -> SilverEvidenceOcr:
    return session.exec(
        select(SilverEvidenceOcr).where(SilverEvidenceOcr.raw_file_id == raw_file_id).order_by(SilverEvidenceOcr.id.desc())
    ).first()


# ------------------------------ plan ------------------------------


def test_plan_has_every_variant():
    plan = Counter(plan_variants(30))
    assert sum(plan.values()) == 30
    assert set(plan) == {
        "full", "no_name", "low_quality", VARIANT_DUPLICATE, VARIANT_NEAR_DUPLICATE,
        VARIANT_PDF_TEXT, VARIANT_PDF_SCAN, VARIANT_PHOTO, VARIANT_TEMPLATE_BASE, VARIANT_TEMPLATE_TWIN,
    }
    # ค่าเริ่มต้น 30 = ชุดเดิม 24 ใบเท่าเดิม + fixture อย่างละใบ
    assert (plan["full"], plan["no_name"], plan["low_quality"], plan[VARIANT_DUPLICATE]) == (11, 5, 4, 4)
    for single in (
        VARIANT_NEAR_DUPLICATE, VARIANT_PDF_TEXT, VARIANT_PDF_SCAN, VARIANT_PHOTO,
        VARIANT_TEMPLATE_BASE, VARIANT_TEMPLATE_TWIN,
    ):
        assert plan[single] == 1, single
    assert len(plan_variants(10)) == 10
    with pytest.raises(SeedAborted):
        plan_variants(9)


def test_compared_files_are_planned_before_the_files_compared_against_them():
    plan = plan_variants(12)
    assert plan.index(VARIANT_TEMPLATE_BASE) < plan.index(VARIANT_TEMPLATE_TWIN)
    first_copy = min(i for i, v in enumerate(plan) if v in (VARIANT_DUPLICATE, VARIANT_NEAR_DUPLICATE))
    assert all(v in (VARIANT_DUPLICATE, VARIANT_NEAR_DUPLICATE) for v in plan[first_copy:])


# ------------------------------ populate ------------------------------


def test_every_demo_participation_has_file_and_ocr_with_mixed_decisions(session, storage, world):
    report = populate(
        session, storage, ReadsEverythingOcr(world["text"]), now=NOW, count=12,
        font_path=THAI_FONT, log=lambda _: None,
    )

    demo_files = session.exec(select(RawFile).where(RawFile.source_system == SOURCE_DEMO)).all()
    assert len(demo_files) == 12 == report.participations
    for raw_file in demo_files:
        # ไฟล์อยู่ใน storage จริง และ OCR มีผลของไฟล์นั้น
        assert storage.get_object_bytes(raw_file.bucket, raw_file.object_key)
        assert session.exec(
            select(SilverEvidenceOcr).where(SilverEvidenceOcr.raw_file_id == raw_file.id)
        ).first()

    decisions = _decisions(session)
    _assert_designed_fixtures_flagged(report, 12, twin_flagged=True)
    assert decisions["flagged"] >= _flagged_when_ocr_cannot_veto(12)
    assert decisions["auto_approved"] > 0
    assert sum(decisions.values()) == 12


def test_flagged_is_guaranteed_even_when_ocr_reads_nothing(session, storage, world):
    """flagged ตัดสินจาก checksum / pHash ไม่ใช่ OCR — OCR ตาบอดก็ยังโดนครบ

    ใบ PDF ที่มี text layer ไม่ผ่าน OCR เลย จึงอาจ auto_approved ได้แม้ OCR ตาบอด
    """
    report = populate(session, storage, BlindOcr(), now=NOW, count=10, font_path=THAI_FONT, log=lambda _: None)
    decisions = _decisions(session)
    text_layer_auto = report.decisions[VARIANT_PDF_TEXT]["auto_approved"]
    _assert_designed_fixtures_flagged(report, 10, twin_flagged=True)
    assert decisions["flagged"] >= _flagged_when_ocr_cannot_veto(10)
    # ส่วนเกิน (ถ้ามี) ต้องเป็นภาพคล้ายเท่านั้น ไม่มีทางเป็นไฟล์ซ้ำเป๊ะนอกเคส C
    exact = session.exec(select(SilverEvidenceOcr).where(SilverEvidenceOcr.match_kind == MatchKind.exact)).all()
    assert len(exact) == plan_variants(10).count(VARIANT_DUPLICATE)
    assert decisions["auto_approved"] <= text_layer_auto + 0, "OCR ตาบอด ใบที่ auto ได้มีแค่ PDF text layer"
    assert decisions["needs_review"] == 10 - decisions["flagged"] - decisions["auto_approved"]


def test_respects_status_capacity_time_and_past_activities(session, storage, world):
    populate(
        session, storage, ReadsEverythingOcr(world["text"]), now=NOW, count=12,
        font_path=THAI_FONT, log=lambda _: None,
    )
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


def test_originals_keep_their_hours_and_copies_are_exact_or_near(session, storage, world):
    populate(session, storage, BlindOcr(), now=NOW, count=10, font_path=THAI_FONT, log=lambda _: None)
    originals = session.exec(select(RawFile).where(RawFile.source_system == SOURCE_DEMO_ORIGINAL)).all()
    plan = plan_variants(10)
    assert len(originals) == plan.count(VARIANT_DUPLICATE) + plan.count(VARIANT_NEAR_DUPLICATE)
    exact = near = 0
    for original in originals:
        owner = session.get(Participation, original.participation_id)
        assert owner.evidence_status == EvidenceStatus.approved
        assert owner.hours_earned == 3
        assert original.phash is not None, "ใบต้นฉบับต้องมี pHash ไม่งั้นชั้น near จับสำเนาไม่ได้"
        copies = session.exec(
            select(RawFile).where(RawFile.checksum == original.checksum, RawFile.id != original.id)
        ).all()
        if copies:
            assert len(copies) == 1 and copies[0].source_system == SOURCE_DEMO
            exact += 1
            continue
        # สำเนาย่อ+บีบอัด: การเข้าร่วมของกิจกรรมเดียวกันที่เป็น JPEG และ pHash ใกล้ต้นฉบับ
        jpeg = [
            f for f in session.exec(select(RawFile).where(RawFile.content_type == "image/jpeg")).all()
            if session.get(Participation, f.participation_id).activity_id == owner.activity_id
        ]
        assert len(jpeg) == 1 and jpeg[0].checksum != original.checksum
        assert phash_distance(jpeg[0].phash, original.phash) <= settings.ocr_phash_near_bits
        near += 1
    assert (exact, near) == (plan.count(VARIANT_DUPLICATE), 1)


def test_case_a_near_copy_of_original_is_flagged_near_cross_student(session, storage, world):
    """เคส A: สำเนาจริง (ชื่อเจ้าของเดิม) ย่อ+บีบอัดใหม่ → flagged near cross_student ชี้ใบต้นฉบับ"""
    report = populate(session, storage, BlindOcr(), now=NOW, count=10, font_path=THAI_FONT, log=lambda _: None)

    near_rows = session.exec(select(SilverEvidenceOcr).where(SilverEvidenceOcr.match_kind == MatchKind.near)).all()
    against_original = [
        r for r in near_rows
        if session.get(Participation, r.duplicate_of_participation_id).evidence_status == EvidenceStatus.approved
        and session.exec(
            select(RawFile).where(
                RawFile.participation_id == r.duplicate_of_participation_id,
                RawFile.source_system == SOURCE_DEMO_ORIGINAL,
            )
        ).first()
    ]

    assert report.decisions[VARIANT_NEAR_DUPLICATE] == Counter(flagged=1)
    assert len(against_original) == 1
    row = against_original[0]
    assert row.duplicate_reason == DuplicateReason.cross_student
    original = session.get(Participation, row.duplicate_of_participation_id)
    borrower = session.get(Participation, row.participation_id)
    assert original.student_id != borrower.student_id and original.activity_id == borrower.activity_id


def test_case_c_exact_copy_is_flagged_exact(session, storage, world):
    report = populate(session, storage, BlindOcr(), now=NOW, count=10, font_path=THAI_FONT, log=lambda _: None)

    exact_rows = session.exec(select(SilverEvidenceOcr).where(SilverEvidenceOcr.match_kind == MatchKind.exact)).all()

    assert len(exact_rows) == plan_variants(10).count(VARIANT_DUPLICATE)
    assert report.decisions[VARIANT_DUPLICATE] == Counter(flagged=len(exact_rows))
    assert all(r.duplicate_reason == DuplicateReason.cross_student for r in exact_rows)


@needs_thai_font
def test_case_b_template_twin_is_near_by_phash_but_vetoed_by_different_text(session, storage, world):
    """เคส B: เทมเพลตเดียวกันคนละคน pHash ≤ threshold ทั้งคู่ OCR อ่านได้ ข้อความต่างกันชัด → ไม่ flag"""
    report = populate(session, storage, CertificateTextOcr(session), now=NOW, count=12, font_path=THAI_FONT, log=lambda _: None)
    base_raw, twin_raw = _raw_by_marker(session, "TB"), _raw_by_marker(session, "TT")
    base_ocr, twin_ocr = _latest_ocr(session, base_raw.id), _latest_ocr(session, twin_raw.id)
    base_p = session.get(Participation, base_raw.participation_id)
    twin_p = session.get(Participation, twin_raw.participation_id)

    # เข้าชั้น near จริง (ไม่ใช่หลุดเพราะ pHash ห่าง) และคนละคนคนละกิจกรรม
    assert phash_distance(base_raw.phash, twin_raw.phash) <= settings.ocr_phash_near_bits
    assert base_p.student_id != twin_p.student_id and base_p.activity_id != twin_p.activity_id
    # เงื่อนไข veto ครบ: อ่านออกทั้งคู่ + ข้อความต่างกันชัด
    assert min(len(base_ocr.extracted_text), len(twin_ocr.extracted_text)) >= settings.ocr_text_veto_min_chars
    assert text_similarity(base_ocr.extracted_text, twin_ocr.extracted_text) < settings.ocr_text_veto_max_similarity
    # ผล: ไม่ flag
    assert twin_ocr.is_duplicate is False and twin_ocr.match_kind is None and twin_ocr.duplicate_reason is None
    assert report.decisions[VARIANT_TEMPLATE_TWIN]["flagged"] == 0
    # เคส A / C ยังโดนตามปกติแม้ OCR อ่านข้อความได้
    assert report.decisions[VARIANT_NEAR_DUPLICATE] == Counter(flagged=1)
    assert report.decisions[VARIANT_DUPLICATE]["flagged"] == plan_variants(12).count(VARIANT_DUPLICATE)


def test_case_b_template_twin_stays_flagged_when_ocr_cannot_tell_the_texts_apart(session, storage, world):
    """ข้อความเหมือนกันทุกใบ (OCR ปลอมอ่านทุกชื่อ) → veto ไม่ทำงาน คง flag near ไว้ (กัน false negative)"""
    report = populate(
        session, storage, ReadsEverythingOcr(world["text"]), now=NOW, count=12,
        font_path=THAI_FONT, log=lambda _: None,
    )
    twin_ocr = _latest_ocr(session, _raw_by_marker(session, "TT").id)

    assert twin_ocr.match_kind == MatchKind.near
    assert report.decisions[VARIANT_TEMPLATE_TWIN] == Counter(flagged=1)


@needs_thai_font
def test_pdf_fixtures_take_the_text_layer_and_ocr_paths(session, storage, world):
    """pdf_text อ่าน text layer (ความมั่นใจตาม config ไม่ใช่ของ OCR) · pdf_scan ผ่าน OCR จริง"""
    report = populate(
        session, storage, ReadsEverythingOcr(world["text"]), now=NOW, count=12,
        font_path=THAI_FONT, log=lambda _: None,
    )

    pdf_rows = session.exec(
        select(SilverEvidenceOcr).join(RawFile, RawFile.id == SilverEvidenceOcr.raw_file_id)
        .where(RawFile.content_type == "application/pdf")
    ).all()

    assert sorted(r.ocr_confidence for r in pdf_rows) == [0.9, settings.ocr_pdf_text_layer_confidence]
    text_layer = next(r for r in pdf_rows if r.ocr_confidence == settings.ocr_pdf_text_layer_confidence)
    assert "มหาวิทยาลัยทักษิณ" in text_layer.extracted_text, "ข้อความจาก text layer จริง ไม่ใช่ข้อความ OCR ปลอม"
    assert report.decisions[VARIANT_PDF_TEXT] == Counter(auto_approved=1)
    # pdf_scan: OCR ปลอมให้ข้อความเหมือนกันทุกใบ text veto จึงทำงานไม่ได้ — ถ้าภาพ render ของมันแตะ
    # threshold กับใบเทมเพลตเดียวกัน (เช่น low_quality ที่เบลอจนเหลือแต่กรอบ) จะถูก flag แบบ near
    # ตามกฎ "veto ไม่ได้ → คง flag" (ดู _assert_designed_fixtures_flagged) ส่วนอย่างอื่นต้อง auto
    scan_row = next(r for r in pdf_rows if r.ocr_confidence != settings.ocr_pdf_text_layer_confidence)
    if scan_row.decision.value == "flagged":
        scan_raw = session.get(RawFile, scan_row.raw_file_id)
        others = session.exec(
            select(RawFile).where(
                RawFile.participation_id == scan_row.duplicate_of_participation_id, RawFile.id < scan_raw.id
            )
        ).all()
        assert scan_row.match_kind == MatchKind.near, "pdf_scan ห้ามโดน exact — ไฟล์ไม่ซ้ำใคร"
        assert min(phash_distance(scan_raw.phash, o.phash) for o in others if o.phash) <= settings.ocr_phash_near_bits
    else:
        assert report.decisions[VARIANT_PDF_SCAN] == Counter(auto_approved=1)


def test_photo_with_auto_worthy_ocr_score_still_needs_review(session, storage, world):
    """ภาพถ่ายกิจกรรม (ข้อความแบนเนอร์ + ป้ายชื่อตรงนิสิต/กิจกรรม) คะแนน OCR ผ่านเกณฑ์ auto ครบ
    → ต้องได้ needs_review เพราะเป็นภาพถ่าย ส่วนใบอื่นทุกใบของ seed เป็น certificate"""
    report = populate(
        session, storage, ReadsEverythingOcr(world["text"]), now=NOW, count=12,
        font_path=THAI_FONT, log=lambda _: None,
    )

    photos = session.exec(select(RawFile).where(RawFile.evidence_kind == EvidenceKind.photo)).all()
    assert len(photos) == 1 and photos[0].content_type == "image/jpeg"
    row = _latest_ocr(session, photos[0].id)
    # คะแนนผ่านเกณฑ์ auto ทุกข้อ — ไม่ได้ตกไป review เพราะคะแนนต่ำ
    assert row.ocr_confidence >= settings.ocr_auto_confidence
    assert row.match_score >= settings.ocr_auto_match
    assert row.decision.value == "needs_review"
    assert session.get(Participation, photos[0].participation_id).evidence_status == EvidenceStatus.pending
    assert report.decisions[VARIANT_PHOTO] == Counter(needs_review=1)

    others = session.exec(select(RawFile).where(RawFile.evidence_kind != EvidenceKind.photo)).all()
    assert others and all(r.evidence_kind == EvidenceKind.certificate for r in others)


def test_rerun_refuses_and_remove_cleans_up_only_demo(session, storage, world):
    before = session.exec(select(func.count()).select_from(Participation)).one()
    populate(session, storage, BlindOcr(), now=NOW, count=10, font_path=THAI_FONT, log=lambda _: None)
    with pytest.raises(SeedAborted):
        populate(session, storage, BlindOcr(), now=NOW, count=10, font_path=THAI_FONT, log=lambda _: None)

    keys = [(f.bucket, f.object_key) for f in session.exec(select(RawFile)).all()]
    removed, files = remove_demo(session, storage)
    session.commit()

    assert removed == 10
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
