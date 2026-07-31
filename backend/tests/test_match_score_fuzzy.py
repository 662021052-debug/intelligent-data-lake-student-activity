"""match_score ต้องทน OCR ภาษาไทยอ่านเพี้ยนไม่กี่ตัว แต่ต้องไม่หลวมจนจับคู่ผิดกิจกรรม

เดิมเทียบด้วย substring ตรง ๆ ชื่อกิจกรรมไทยเขียนติดกันไม่มีช่องว่าง ผิดตัวเดียว
คะแนนส่วนนั้นจึงเหลือ 0 ทันที (ใบประกาศจริงตกไปกอง needs_review ทั้งที่ควรผ่าน)
"""
from datetime import datetime
from types import SimpleNamespace

import pytest

from app.silver import _activity_score, _norm, compute_match_score

STUDENT = SimpleNamespace(full_name="ทัศนัย แสงจันทร์")
ACTIVITY = SimpleNamespace(name="ค่ายอาสาพัฒนาชนบท", start_at=datetime(2025, 10, 14))

AUTO_APPROVE_MATCH = 0.7  # settings.ocr_auto_match


def _certificate(name="นายทัศนัย แสงจันทร์", activity="ค่ายอาสาพัฒนาชนบท", year="2568"):
    return f"เกียรติบัตรฉบับนี้ให้ไว้เพื่อแสดงว่า {name} ได้เข้าร่วมกิจกรรม {activity} เมื่อวันที่ 14 ตุลาคม {year}"


def test_perfect_certificate_scores_full():
    assert compute_match_score(_certificate(), STUDENT, ACTIVITY) == pytest.approx(1.0)


@pytest.mark.parametrize(
    "typo",
    [
        "ค่ายอาสาพัฒนาชนบห",   # ท -> ห (ตัวท้าย)
        "ค่ายอาสาพัฒนาชนบท",   # ถูกต้อง
        "ค่ายอาสาพัฒมาชนบท",   # น -> ม (กลางคำ)
        "คายอาสาพัฒนาชนบท",    # หายสระ
    ],
)
def test_activity_name_with_one_ocr_typo_still_auto_approves(typo):
    score = compute_match_score(_certificate(activity=typo), STUDENT, ACTIVITY)
    assert score >= AUTO_APPROVE_MATCH, f"{typo!r} ได้ {score}"


def test_two_typos_in_a_long_name_still_recognised():
    score = compute_match_score(
        _certificate(activity="ค่ายอาสาพัฒมาชนบห"), STUDENT, ACTIVITY
    )
    assert score >= AUTO_APPROVE_MATCH


def test_different_activity_is_not_matched():
    """กิจกรรมอื่นต้องไม่ได้คะแนนชื่อกิจกรรม ไม่งั้นเอาใบประกาศงานอื่นมาใช้ผ่านได้"""
    assert _activity_score("ค่ายอาสาพัฒนาชนบท", _norm(_certificate(activity="ค่ายอนุรักษ์สิ่งแวดล้อม"))) == 0.0
    score = compute_match_score(
        _certificate(activity="อบรมนาฏศิลป์และดนตรีไทย"), STUDENT, ACTIVITY
    )
    assert score < AUTO_APPROVE_MATCH


def test_certificate_without_student_name_needs_review():
    """ป้ายงาน/ภาพหมู่ที่ไม่มีชื่อผู้เข้าร่วม ต้องไม่ผ่านอัตโนมัติ"""
    text = "ค่ายอาสาพัฒนาชนบท ผู้เข้าร่วมกิจกรรม 14 ตุลาคม 2568"
    score = compute_match_score(text, STUDENT, ACTIVITY)
    assert score < AUTO_APPROVE_MATCH


def test_student_name_typo_in_surname_still_passes_with_activity_and_date():
    score = compute_match_score(
        _certificate(name="นายทัศนัย แสงจันหร์"), STUDENT, ACTIVITY
    )
    assert score >= AUTO_APPROVE_MATCH


def test_unrelated_document_scores_zero():
    text = "ใบเสร็จรับเงิน ค่าบำรุงการศึกษา ภาคเรียนที่ 1 ปีการศึกษา 2568"
    assert compute_match_score(text, STUDENT, ACTIVITY) < 0.3


def test_empty_ocr_text_scores_zero():
    assert compute_match_score("", STUDENT, ACTIVITY) == 0.0
