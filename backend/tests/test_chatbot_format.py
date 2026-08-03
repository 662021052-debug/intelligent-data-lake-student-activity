"""Humanized chatbot answers (PHASE_Chatbot_Humanize_Answers.md).

Pure unit tests over ``app.chatbot_format`` — no DB, no LLM. The formatters are
deterministic, so every expectation here is exact.
"""
import pytest

from app import chatbot_format as fmt

# Raw column names that must never reach the user.
RAW_COLUMNS = [
    "available_seats", "category_name", "participant_count", "max_participants",
    "earned_hours", "required_hours", "activity_type", "subcategory_name",
]


def assert_no_raw_columns(answer: str):
    for column in RAW_COLUMNS:
        assert f"{column}:" not in answer, f"raw column {column!r} leaked into: {answer}"
        assert column not in answer, f"raw column {column!r} leaked into: {answer}"


def _activity(name, *, hours=4, category="TSU รับใช้สังคม", joined=0, cap=10,
              activity_type="อาสา", subcategory="จิตอาสา"):
    return {
        "name": name,
        "activity_type": activity_type,
        "hours": hours,
        "category_name": category,
        "subcategory_name": subcategory,
        "participant_count": joined,
        "max_participants": cap,
    }


# ------------------------------ small helpers -------------------------------

@pytest.mark.parametrize(
    "value,expected",
    [(4.0, "4"), (4, "4"), (1.5, "1.5"), (0.0, "0"), (12.0, "12")],
)
def test_fmt_num_drops_trailing_zeros(value, expected):
    assert fmt.fmt_num(value) == expected


def test_units_are_thai_words():
    assert fmt.fmt_hours(4.0) == "4 ชม."
    assert fmt.fmt_seats(98) == "98 ที่"


def test_seats_left_never_negative():
    assert fmt.seats_left(_activity("ก", joined=12, cap=10)) == 0
    assert fmt.seats_left(_activity("ก", joined=2, cap=10)) == 8


def test_numbered_truncates_long_lists():
    lines = fmt.numbered([f"รายการ {i}" for i in range(1, 15)])
    assert lines[0] == "1. รายการ 1"
    assert len(lines) == fmt.MAX_LIST_ITEMS + 1          # 10 items + the tail line
    assert lines[-1] == "…และอีก 4 กิจกรรม พิมพ์ถามเจาะจงได้"


def test_numbered_short_list_has_no_tail():
    lines = fmt.numbered(["ก", "ข"])
    assert lines == ["1. ก", "2. ข"]


# --------------------------- open activities intent -------------------------

def test_open_activities_sorted_by_free_seats_desc():
    rows = [
        _activity("น้อยที่สุด", joined=9, cap=10),   # 1 seat
        _activity("มากที่สุด", joined=2, cap=100),   # 98 seats
        _activity("กลาง", joined=5, cap=20),         # 15 seats
    ]
    answer = fmt.open_activities(rows)
    order = [answer.index(n) for n in ("มากที่สุด", "กลาง", "น้อยที่สุด")]
    assert order == sorted(order), f"not sorted by free seats: {answer}"
    assert answer.startswith("ตอนนี้มี 3 กิจกรรมที่ยังเปิดรับสมัคร")
    assert "เหลือ 98 ที่" in answer
    assert_no_raw_columns(answer)


def test_open_activities_drops_full_ones():
    rows = [_activity("เต็มแล้ว", joined=10, cap=10), _activity("ยังว่าง", joined=1, cap=10)]
    answer = fmt.open_activities(rows)
    assert "ยังว่าง" in answer
    assert "เต็มแล้ว" not in answer
    assert "ตอนนี้มี 1 กิจกรรม" in answer


def test_open_activities_all_full_is_a_sentence():
    answer = fmt.open_activities([_activity("เต็มแล้ว", joined=10, cap=10)])
    assert answer == "ตอนนี้ไม่มีกิจกรรมที่เปิดรับเพิ่มแล้ว ลองถามใหม่อีกครั้งภายหลังนะ"


def test_open_activities_empty():
    assert "ไม่มีกิจกรรมที่เปิดรับเพิ่มแล้ว" in fmt.open_activities([])


def test_open_activities_line_shape():
    answer = fmt.open_activities([_activity("ปลูกป่าชายเลน", hours=4, joined=2, cap=100)])
    assert "1. ปลูกป่าชายเลน — TSU รับใช้สังคม · 4 ชม. · เหลือ 98 ที่" in answer


def test_open_activities_truncates_over_ten():
    rows = [_activity(f"กิจกรรม {i}", joined=i, cap=100) for i in range(13)]
    answer = fmt.open_activities(rows)
    assert "…และอีก 3 กิจกรรม พิมพ์ถามเจาะจงได้" in answer


# ------------------------------- hours intent -------------------------------

def _hours_row(name, earned, required, completed):
    return {
        "category_name": name, "earned_hours": earned,
        "required_hours": required, "completed": completed,
    }


def test_my_hours_reads_as_a_sentence():
    rows = [_hours_row("หมวดหนึ่ง", 8, 8, 1), _hours_row("หมวดสอง", 4, 12, 0)]
    answer = fmt.my_hours(rows, 60)
    assert answer.startswith("ตอนนี้คุณสะสมชั่วโมงที่อนุมัติแล้ว 12 ชม. จากเกณฑ์ 60 ชม.")
    assert "ผ่านครบ 1 จาก 2 หมวด" in answer
    assert "หมวดหนึ่ง 8/8 ชม. (ครบแล้ว)" in answer
    assert "หมวดสอง 4/12 ชม. (ขาดอีก 8 ชม.)" in answer
    assert "เหลืออีก 48 ชม. จึงจะครบเกณฑ์" in answer
    assert_no_raw_columns(answer)


def test_my_hours_celebrates_when_complete():
    rows = [_hours_row("หมวดหนึ่ง", 30, 30, 1), _hours_row("หมวดสอง", 30, 30, 1)]
    answer = fmt.my_hours(rows, 60)
    assert "ครบตามเกณฑ์แล้ว" in answer
    assert "เหลืออีก" not in answer


def test_my_hours_with_no_rows():
    assert "ยังไม่มีชั่วโมงกิจกรรมที่อนุมัติ" in fmt.my_hours([], 60)


# ------------------------------ missing intent ------------------------------

def test_missing_single_category_is_one_sentence():
    answer = fmt.missing_categories([_hours_row("TSU รับใช้สังคม", 4, 12, 0)])
    assert answer == (
        "คุณยังขาดหมวดTSU รับใช้สังคม (ได้ 4/12 ชม.) — ต้องเก็บเพิ่มอีก 8 ชม. "
        "แนะนำให้เข้าร่วมกิจกรรมในหมวดนี้"
    )


def test_missing_multiple_categories_is_a_numbered_list():
    rows = [_hours_row("หมวดหนึ่ง", 2, 8, 0), _hours_row("หมวดสอง", 4, 12, 0)]
    answer = fmt.missing_categories(rows)
    assert answer.startswith("คุณยังเก็บชั่วโมงไม่ครบ 2 หมวด รวมต้องเก็บเพิ่มอีก 14 ชม.:")
    assert "1. หมวดหนึ่ง — ได้ 2/8 ชม. ขาดอีก 6 ชม." in answer
    assert "2. หมวดสอง — ได้ 4/12 ชม. ขาดอีก 8 ชม." in answer
    assert_no_raw_columns(answer)


def test_missing_none_congratulates():
    assert "ครบทุกหมวดแล้ว" in fmt.missing_categories([])


# ------------------------------ required intent -----------------------------

def test_required_activities_list():
    rows = [_activity("ปฐมนิเทศ", hours=6, category="TSU พัฒนาตน")]
    answer = fmt.required_activities(rows)
    assert answer.startswith("มีกิจกรรมบังคับที่ต้องเข้าร่วม 1 กิจกรรม:")
    assert "1. ปฐมนิเทศ — TSU พัฒนาตน · 6 ชม." in answer
    assert_no_raw_columns(answer)


def test_required_activities_without_category():
    rows = [dict(_activity("ปฐมนิเทศ"), category_name=None)]
    assert "ไม่ระบุหมวด" in fmt.required_activities(rows)


def test_required_activities_empty():
    assert fmt.required_activities([]) == "ตอนนี้ยังไม่มีกิจกรรมบังคับที่เปิดให้เข้าร่วม"


# ---------------------------- recommend intent ------------------------------

def test_recommend_for_missing_starts_with_recommend_prefix():
    rows = [_activity("ปลูกป่า", joined=1, cap=10), _activity("เก็บขยะ", joined=8, cap=10)]
    answer = fmt.recommend_for_missing(["TSU รับใช้สังคม"], rows)
    assert answer.startswith("แนะนำ: คุณยังขาดหมวดTSU รับใช้สังคม")
    # 9 free seats beats 2 free seats
    assert answer.index("ปลูกป่า") < answer.index("เก็บขยะ")
    assert_no_raw_columns(answer)


def test_recommend_for_missing_with_nothing_open():
    answer = fmt.recommend_for_missing(["หมวดหนึ่ง"], [_activity("ค่ายที่เต็มแล้ว", joined=10, cap=10)])
    assert "ยังไม่มีกิจกรรมในหมวดนี้ที่เปิดรับสมัครอยู่" in answer
    assert "ค่ายที่เต็มแล้ว" not in answer


def test_recommend_alternatives_names_the_full_activity():
    full = _activity("ค่ายอาสา", joined=10, cap=10)
    answer = fmt.recommend_alternatives(full, [_activity("ปลูกป่า", joined=2, cap=30)])
    assert answer.startswith('แนะนำ: กิจกรรม "ค่ายอาสา" เต็มแล้ว')
    assert "จิตอาสา" in answer          # same-subcategory explanation
    assert "1. ปลูกป่า — 4 ชม. · เหลือ 28 ที่" in answer
    assert_no_raw_columns(answer)


def test_recommend_alternatives_when_none_left():
    full = _activity("ค่ายอาสา", joined=10, cap=10)
    answer = fmt.recommend_alternatives(full, [])
    assert "ยังไม่มีกิจกรรมอื่นในหมวดจิตอาสาที่เปิดรับแทนได้" in answer


# ------------------------ generic Text-to-SQL fallback ----------------------

def test_generic_rows_no_longer_dumps_key_values():
    """This is exactly the shape the user complained about:
    ``name: ..., category_name: ..., hours: 4.0, available_seats: 98``."""
    rows = [
        {"name": "ปลูกป่า", "category_name": "TSU รับใช้สังคม",
         "hours": 4.0, "available_seats": 98},
        {"name": "ค่ายอาสา", "category_name": "TSU รับใช้สังคม",
         "hours": 6.0, "available_seats": 12},
    ]
    answer = fmt.generic_rows(rows)
    assert "available_seats" not in answer
    assert "hours: 4.0" not in answer
    assert answer.startswith("จากข้อมูลของคุณ พบ 2 รายการ:")
    assert "1. ปลูกป่า — หมวด TSU รับใช้สังคม · ชั่วโมง 4 ชม. · ที่ว่าง 98 ที่" in answer


def test_generic_rows_single_scalar_is_a_sentence():
    assert fmt.generic_rows([{"count": 3}]) == "คำตอบคือ 3"


def test_generic_rows_single_row():
    answer = fmt.generic_rows([{"name": "ปลูกป่า", "hours": 4.0}])
    assert answer == "จากข้อมูลของคุณ: ปลูกป่า — ชั่วโมง 4 ชม."


def test_generic_rows_booleans_are_words():
    answer = fmt.generic_rows([{"category_name": "หมวดหนึ่ง", "completed": 0, "is_required": 1}])
    assert "ยังไม่ครบ" in answer
    assert "บังคับ" in answer
    assert "completed" not in answer


def test_generic_rows_unknown_column_loses_underscores():
    answer = fmt.generic_rows([{"name": "ก", "some_odd_alias": 7}])
    assert "some_odd_alias" not in answer
    assert "some odd alias 7" in answer


def test_generic_rows_hides_surrogate_keys():
    """A "SELECT *" from the LLM must not print 'student key 1 · date key 20250902'."""
    rows = [
        {"activity_key": 3, "name": "ค่ายผู้นำ", "date_key": 20250902,
         "subcategory_key": 1, "category_key": 1, "hours": 6.0, "id": 3,
         "student_code": "650811001"},
        {"activity_key": 4, "name": "ปลูกป่า", "date_key": 20250916,
         "subcategory_key": 2, "category_key": 2, "hours": 4.0, "id": 4,
         "student_code": "650811001"},
    ]
    answer = fmt.generic_rows(rows)
    for noise in ("activity key", "date key", "subcategory key", "category key",
                  "student code", "20250902"):
        assert noise not in answer, f"{noise!r} leaked into: {answer}"
    assert "1. ค่ายผู้นำ — ชั่วโมง 6 ชม." in answer


def test_generic_rows_translates_approval_status():
    rows = [{"name": "ก", "approval_status": "approved"},
            {"name": "ข", "approval_status": "pending"}]
    answer = fmt.generic_rows(rows)
    assert "สถานะ อนุมัติแล้ว" in answer
    assert "สถานะ รออนุมัติ" in answer
    assert "approved" not in answer and "pending" not in answer


def test_generic_rows_all_columns_hidden_still_shows_values():
    answer = fmt.generic_rows([{"student_key": 1, "category_key": 2},
                               {"student_key": 1, "category_key": 3}])
    assert "1. 1 · 2" in answer
    assert "student_key" not in answer


def test_generic_rows_empty():
    assert "ไม่พบข้อมูลที่ตรงกับคำถามของคุณ" in fmt.generic_rows([])


def test_generic_rows_truncates_long_results():
    rows = [{"name": f"ก {i}", "hours": 1} for i in range(12)]
    assert "…และอีก 2 รายการ พิมพ์ถามเจาะจงได้" in fmt.generic_rows(rows)
