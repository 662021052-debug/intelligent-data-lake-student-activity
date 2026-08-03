"""Thai answer formatting for the chatbot's canned intents.

The canned intents deliberately never call the LLM (they must stay fast and work
with ``LLM_BACKEND=stub``), so the "sound like a human" job lives here: a set of
pure, deterministic functions that turn database rows into natural Thai prose.

Rules of the house (see ``PHASE_Chatbot_Humanize_Answers.md``):
  * never show a raw column name (``available_seats``, ``category_name``, …)
  * hours end in "ชม.", seats end in "ที่"
  * long lists are truncated with a hint to ask something more specific
  * everything is deterministic — the same rows always produce the same string
"""
from __future__ import annotations

from typing import Any, Iterable, Sequence

# Show at most this many items before collapsing the rest into a "และอีก k …" line.
MAX_LIST_ITEMS = 10


def fmt_num(value: Any) -> str:
    """Format a number the way a person writes it: 4 not 4.0, 1.5 stays 1.5."""
    try:
        return f"{float(value):g}"
    except (TypeError, ValueError):
        return str(value)


def fmt_hours(value: Any) -> str:
    return f"{fmt_num(value)} ชม."


def fmt_seats(value: Any) -> str:
    return f"{fmt_num(value)} ที่"


def numbered(items: Sequence[str], *, unit: str = "กิจกรรม", limit: int = MAX_LIST_ITEMS) -> list[str]:
    """Render ``items`` as "1. …" lines, collapsing the tail past ``limit``."""
    shown = list(items[:limit])
    lines = [f"{i}. {text}" for i, text in enumerate(shown, start=1)]
    hidden = len(items) - len(shown)
    if hidden > 0:
        lines.append(f"…และอีก {hidden} {unit} พิมพ์ถามเจาะจงได้")
    return lines


def seats_left(row: dict) -> int:
    """Remaining places in an activity (never negative)."""
    try:
        return max(0, int(row["max_participants"]) - int(row["participant_count"]))
    except (KeyError, TypeError, ValueError):
        return 0


def sort_by_seats(rows: Iterable[dict]) -> list[dict]:
    """Most seats first; ties broken by name so the answer is reproducible."""
    return sorted(rows, key=lambda r: (-seats_left(r), str(r.get("name") or "")))


def with_seats(rows: Iterable[dict]) -> list[dict]:
    """Drop anything already full — a student asking "ลงอันไหนดี" cannot join those."""
    return [r for r in rows if seats_left(r) > 0]


def _activity_line(row: dict, *, show_seats: bool = True, show_category: bool = True) -> str:
    parts = []
    if show_category and row.get("category_name"):
        parts.append(str(row["category_name"]))
    parts.append(fmt_hours(row.get("hours", 0)))
    if show_seats:
        parts.append(f"เหลือ {fmt_seats(seats_left(row))}")
    return f"{row.get('name', '-')} — " + " · ".join(parts)


# --------------------------- intent: open activities ------------------------

def open_activities(rows: Sequence[dict]) -> str:
    available = sort_by_seats(with_seats(rows))
    if not available:
        return "ตอนนี้ไม่มีกิจกรรมที่เปิดรับเพิ่มแล้ว ลองถามใหม่อีกครั้งภายหลังนะ"
    header = f"ตอนนี้มี {len(available)} กิจกรรมที่ยังเปิดรับสมัคร (เรียงตามที่นั่งว่างมากสุด):"
    return "\n".join([header] + numbered([_activity_line(r) for r in available]))


# ------------------------------ intent: my hours ----------------------------

def my_hours(rows: Sequence[dict], total_required: float) -> str:
    if not rows:
        return "ยังไม่มีชั่วโมงกิจกรรมที่อนุมัติในระบบ ลองเข้าร่วมกิจกรรมแล้วส่งหลักฐานดูนะ"

    total_earned = sum(float(r["earned_hours"]) for r in rows)
    done = [r for r in rows if r["completed"]]
    remaining_total = max(0.0, float(total_required) - total_earned)

    header = (
        f"ตอนนี้คุณสะสมชั่วโมงที่อนุมัติแล้ว {fmt_hours(total_earned)} "
        f"จากเกณฑ์ {fmt_hours(total_required)} — ผ่านครบ {len(done)} จาก {len(rows)} หมวด"
    )

    details = []
    for r in rows:
        earned, required = float(r["earned_hours"]), float(r["required_hours"])
        if r["completed"]:
            note = "ครบแล้ว"
        else:
            note = f"ขาดอีก {fmt_hours(required - earned)}"
        details.append(f"{r['category_name']} {fmt_num(earned)}/{fmt_num(required)} ชม. ({note})")

    lines = [header, "แยกตามหมวด: " + ", ".join(details)]
    if remaining_total <= 0:
        lines.append("คุณเก็บชั่วโมงครบตามเกณฑ์แล้ว 🎉")
    else:
        lines.append(f"เหลืออีก {fmt_hours(remaining_total)} จึงจะครบเกณฑ์")
    return "\n".join(lines)


# --------------------------- intent: missing categories ---------------------

def missing_categories(rows: Sequence[dict]) -> str:
    if not rows:
        return "ยินดีด้วย! คุณเก็บชั่วโมงครบทุกหมวดแล้ว ไม่ต้องเก็บเพิ่มอีก 🎉"

    def gap(r: dict) -> float:
        return float(r["required_hours"]) - float(r["earned_hours"])

    if len(rows) == 1:
        r = rows[0]
        return (
            f"คุณยังขาดหมวด{r['category_name']} "
            f"(ได้ {fmt_num(r['earned_hours'])}/{fmt_num(r['required_hours'])} ชม.) "
            f"— ต้องเก็บเพิ่มอีก {fmt_hours(gap(r))} "
            "แนะนำให้เข้าร่วมกิจกรรมในหมวดนี้"
        )

    total_gap = sum(gap(r) for r in rows)
    header = (
        f"คุณยังเก็บชั่วโมงไม่ครบ {len(rows)} หมวด "
        f"รวมต้องเก็บเพิ่มอีก {fmt_hours(total_gap)}:"
    )
    items = [
        f"{r['category_name']} — ได้ {fmt_num(r['earned_hours'])}/{fmt_num(r['required_hours'])} ชม. "
        f"ขาดอีก {fmt_hours(gap(r))}"
        for r in rows
    ]
    return "\n".join(
        [header]
        + numbered(items, unit="หมวด")
        + ['แนะนำให้เข้าร่วมกิจกรรมในหมวดเหล่านี้ — พิมพ์ "แนะนำกิจกรรม" เพื่อดูกิจกรรมที่ยังเปิดรับ']
    )


# --------------------------- intent: required activities --------------------

def required_activities(rows: Sequence[dict]) -> str:
    if not rows:
        return "ตอนนี้ยังไม่มีกิจกรรมบังคับที่เปิดให้เข้าร่วม"
    header = f"มีกิจกรรมบังคับที่ต้องเข้าร่วม {len(rows)} กิจกรรม:"
    items = [
        f"{r['name']} — {r['category_name'] or 'ไม่ระบุหมวด'} · {fmt_hours(r['hours'])}"
        for r in rows
    ]
    return "\n".join([header] + numbered(items))


# ------------------------------ intent: recommend ---------------------------

def recommend_for_missing(missing_names: Sequence[str], activities: Sequence[dict]) -> str:
    available = sort_by_seats(with_seats(activities))
    names = " และ ".join(missing_names)
    if not available:
        return (
            f"แนะนำ: คุณยังขาดหมวด{names} แต่ตอนนี้ยังไม่มีกิจกรรมในหมวดนี้ที่เปิดรับสมัครอยู่ "
            "ลองกลับมาถามใหม่เมื่อมีกิจกรรมใหม่เปิดนะ"
        )
    header = (
        f"แนะนำ: คุณยังขาดหมวด{names} "
        "จึงแนะนำกิจกรรมที่นับชั่วโมงในหมวดนี้และยังมีที่ว่าง (เรียงตามที่นั่งว่างมากสุด):"
    )
    return "\n".join([header] + numbered([_activity_line(r) for r in available]))


def recommend_alternatives(activity: dict, rows: Sequence[dict]) -> str:
    available = sort_by_seats(with_seats(rows))
    subcategory = activity.get("subcategory_name") or "หมวดเดียวกัน"
    if not available:
        return (
            f"กิจกรรม \"{activity['name']}\" เต็มแล้ว "
            f"และตอนนี้ยังไม่มีกิจกรรมอื่นในหมวด{subcategory}ที่เปิดรับแทนได้ "
            "ลองกลับมาถามใหม่เมื่อมีกิจกรรมใหม่เปิดนะ"
        )
    header = (
        f"แนะนำ: กิจกรรม \"{activity['name']}\" เต็มแล้ว "
        f"แต่ยังมีอีก {len(available)} กิจกรรมที่นับชั่วโมงหมวดเดียวกัน ({subcategory}) และยังมีที่ว่าง:"
    )
    lines = [_activity_line(r, show_category=False) for r in available]
    return "\n".join([header] + numbered(lines))


# ---------------------- fallback: generic Text-to-SQL rows ------------------
# The LLM picks its own column aliases, so this is a best-effort humanizer: known
# columns get a Thai label + unit, anything unknown at least loses its underscores.

_COLUMN_LABELS: dict[str, str] = {
    "name": "",                       # used as the row title, never labelled
    "activity_name": "",
    "full_name": "",
    "category_name": "หมวด",
    "subcategory_name": "หมวดย่อย",
    "activity_type": "ประเภท",
    "hours": "ชั่วโมง",
    "earned_hours": "ได้แล้ว",
    "required_hours": "เกณฑ์",
    "remaining_hours": "ยังขาด",
    "max_participants": "รับได้",
    "participant_count": "สมัครแล้ว",
    "available_seats": "ที่ว่าง",
    "seats_available": "ที่ว่าง",
    "remaining_seats": "ที่ว่าง",
    "start_at": "เริ่ม",
    "location": "สถานที่",
    "completed": "สถานะ",
    "is_required": "การเข้าร่วม",
    "approval_status": "สถานะ",
}
_STATUS_WORDS = {
    "approved": "อนุมัติแล้ว",
    "pending": "รออนุมัติ",
    "rejected": "ไม่อนุมัติ",
}
# Surrogate keys and internal codes carry no meaning for a student — a SELECT *
# from the LLM would otherwise print "student key 1 · date key 20250902 · …".
_HIDDEN_COLUMNS = {"id", "student_code", "student_id", "activity_id"}
_HOUR_COLUMNS = {"hours", "earned_hours", "required_hours", "remaining_hours"}
_SEAT_COLUMNS = {"available_seats", "seats_available", "remaining_seats", "max_participants",
                 "participant_count"}
_TITLE_COLUMNS = ("name", "activity_name", "full_name", "category_name", "subcategory_name")


def _is_hidden(column: str) -> bool:
    return column in _HIDDEN_COLUMNS or column.endswith("_key")


def _format_value(column: str, value: Any) -> str:
    if value is None:
        return "-"
    if column == "approval_status":
        return _STATUS_WORDS.get(str(value), str(value))
    if column == "completed":
        return "ครบแล้ว" if value else "ยังไม่ครบ"
    if column == "is_required":
        return "บังคับ" if value else "ไม่บังคับ"
    if column in _HOUR_COLUMNS:
        return fmt_hours(value)
    if column in _SEAT_COLUMNS:
        return fmt_seats(value)
    return str(value)


def _label(column: str) -> str:
    if column in _COLUMN_LABELS:
        return _COLUMN_LABELS[column]
    return column.replace("_", " ").strip()


def _row_sentence(row: dict) -> str:
    title_col = next((c for c in _TITLE_COLUMNS if row.get(c)), None)
    parts = []
    for column, value in row.items():
        if column == title_col or _is_hidden(column):
            continue
        label = _label(column)
        rendered = _format_value(column, value)
        parts.append(f"{label} {rendered}".strip())
    body = " · ".join(parts)
    if title_col is not None:
        return f"{row[title_col]} — {body}" if body else str(row[title_col])
    if body:
        return body
    # Every column was hidden (e.g. "SELECT student_key") — show the bare values
    # rather than an empty bullet.
    return " · ".join(_format_value(c, v) for c, v in row.items())


def generic_rows(rows: Sequence[dict]) -> str:
    """Humanize arbitrary Text-to-SQL result rows (the old key:value dump)."""
    if not rows:
        return "ไม่พบข้อมูลที่ตรงกับคำถามของคุณ ลองถามใหม่ด้วยคำอื่นดูนะ"

    # A single scalar (e.g. COUNT(*)) reads best as a plain sentence.
    if len(rows) == 1 and len(rows[0]) == 1:
        column, value = next(iter(rows[0].items()))
        return f"คำตอบคือ {_format_value(column, value)}"

    if len(rows) == 1:
        return "จากข้อมูลของคุณ: " + _row_sentence(rows[0])

    header = f"จากข้อมูลของคุณ พบ {len(rows)} รายการ:"
    return "\n".join([header] + numbered([_row_sentence(r) for r in rows], unit="รายการ"))
