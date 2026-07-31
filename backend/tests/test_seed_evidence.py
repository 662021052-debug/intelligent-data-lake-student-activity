"""หลักฐานตัวอย่างต้องเป็นใบประกาศจริงที่มีข้อความ และไม่ซ้ำกัน

เดิม seed ใช้ PNG 1x1 ก้อนเดียวซ้ำทุกแถว ทำให้ OCR ไม่มีอะไรให้อ่านและตัวตรวจ
ไฟล์ซ้ำติดธง flagged ใส่ข้อมูลปกติ
"""
import hashlib
import random
from datetime import datetime

import pytest

from seed_evidence import (
    VARIANT_FULL,
    VARIANT_LOW_QUALITY,
    VARIANT_NO_NAME,
    find_thai_font,
    pick_variant,
    render_certificate,
    thai_date,
)

Image = pytest.importorskip("PIL.Image")


def _render(**overrides) -> bytes:
    kwargs = {
        "student_name": "ทัศนัย แสงจันทร์",
        "activity_name": "ค่ายอาสาพัฒนาชนบท",
        "activity_date": datetime(2025, 10, 14),
        "category_path": "จิตอาสาและความรับผิดชอบต่อสังคม › กิจกรรมบำเพ็ญประโยชน์",
        "reference": "TSU-006-00042-A1B2C3",
        "font_path": find_thai_font(),
    }
    kwargs.update(overrides)
    return render_certificate(**kwargs)


def test_renders_a_real_readable_png():
    data = _render()

    image = Image.open(__import__("io").BytesIO(data))
    assert image.format == "PNG"
    # ต้องเป็นภาพขนาดใช้งานได้จริง ไม่ใช่ 1x1 แบบเดิม
    assert image.size == (1000, 700)
    assert len(data) > 5_000


def test_every_certificate_has_a_different_checksum():
    """เลขอ้างอิงไม่ซ้ำ = checksum ไม่ซ้ำ ตัวตรวจไฟล์ซ้ำจึงไม่ติดธงผิด"""
    checksums = {
        hashlib.sha256(_render(reference=f"TSU-001-{i:05d}-ABCDEF")).hexdigest()
        for i in range(5)
    }
    assert len(checksums) == 5


def test_same_activity_different_students_are_different_files():
    a = _render(student_name="ทัศนัย แสงจันทร์", reference="TSU-006-00001-AAAAAA")
    b = _render(student_name="ปาริชาต เรืองฤทธิ์", reference="TSU-006-00002-BBBBBB")
    assert hashlib.sha256(a).hexdigest() != hashlib.sha256(b).hexdigest()


def test_variants_produce_different_images():
    full = _render(variant=VARIANT_FULL)
    no_name = _render(variant=VARIANT_NO_NAME)
    low = _render(variant=VARIANT_LOW_QUALITY)
    assert len({full, no_name, low}) == 3


def test_variant_mix_is_mostly_complete_certificates():
    """ส่วนใหญ่ต้องเป็นใบสมบูรณ์ (ผ่านอัตโนมัติได้) แต่ต้องมีเคสที่ต้องให้คนตรวจปนมาด้วย"""
    rng = random.Random(20260726)
    counts = {VARIANT_FULL: 0, VARIANT_NO_NAME: 0, VARIANT_LOW_QUALITY: 0}
    for _ in range(1000):
        counts[pick_variant(rng)] += 1

    assert counts[VARIANT_FULL] > 600
    assert counts[VARIANT_NO_NAME] > 50
    assert counts[VARIANT_LOW_QUALITY] > 50


def test_thai_date_uses_buddhist_year():
    assert thai_date(datetime(2025, 10, 14)) == "14 ตุลาคม 2568"
    assert thai_date(datetime(2026, 1, 6)) == "6 มกราคม 2569"
