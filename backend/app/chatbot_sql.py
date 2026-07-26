"""Intent routing + Text-to-SQL for the student chatbot (Phase 17).

Answers four kinds of data questions, always scoped to the asking student:
  * HOURS            — "ฉันได้กี่ชั่วโมงแล้ว"        (my accumulated approved hours)
  * MISSING          — "ขาดหมวดไหนบ้าง"              (categories not yet complete)
  * OPEN_ACTIVITIES  — "กิจกรรมอะไรเปิดรับสมัครบ้าง"  (approved + not full)
  * REQUIRED         — "กิจกรรมบังคับมีอะไร"          (is_required activities)

Security model (see the 🔴 section of the phase spec):
  * The four known intents run **server-authored, parameterized SQL** — the student
    id is a bound parameter, so a student can only ever read their own rows. The LLM
    never writes this SQL.
  * A general/unknown data question falls back to LLM Text-to-SQL, but even then the
    student filter is injected structurally: the LLM may only read a ``my_hours`` CTE
    pre-filtered to the current student (never the raw ``gold_student_hours``), and
    its SQL must pass :func:`app.sql_guard.validate_select` before running.
  * Only ``gold_*`` views (and the injected CTE) are ever queried — never the raw
    operational tables.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from sqlalchemy import bindparam, text
from sqlmodel import Session

from app.llm import LlmClient
from app.sql_guard import UnsafeSqlError, validate_select

# Total activity hours required to graduate (sum of all category requirements).
TOTAL_REQUIRED_HOURS = 60


class Intent(str, Enum):
    HOURS = "hours"
    MISSING = "missing"
    OPEN_ACTIVITIES = "open_activities"
    REQUIRED = "required"
    RECOMMEND = "recommend"  # suggest activities for the student's missing categories
    RULES = "rules"          # handled by the RAG path (rag.answer_rules_question)
    GENERAL = "general"      # falls back to LLM Text-to-SQL


@dataclass
class ChatAnswer:
    intent: Intent
    answer: str
    rows: list[dict] = field(default_factory=list)
    needs_student: bool = False  # True if this intent requires a linked student


# ---- Intent routing (keyword based; deterministic and offline) --------------
# Self-reference words that mark a question as being about the asker's own record.
_SELF_WORDS = ("ฉัน", "ผม", "หนู", "ของฉัน", "ตัวเอง", "ของผม", "ของหนู")
_MISSING_WORDS = ("ขาด", "ยังไม่ครบ", "ไม่ครบ", "เหลืออีก", "ต้องเก็บอีก", "ยังขาด")
_OPEN_WORDS = ("เปิดรับ", "รับสมัคร", "สมัคร", "ลงทะเบียน", "เข้าร่วมได้", "ยังรับ")
_REQUIRED_WORDS = ("บังคับ", "ต้องเข้าร่วม", "กิจกรรมบังคับ")
_RECOMMEND_WORDS = ("แนะนำ", "ควรลง", "ควรเข้าร่วม", "ลงอะไรดี", "กิจกรรมไหนดี",
                    "เลือกกิจกรรม", "อยากได้ชั่วโมงเพิ่ม", "ทดแทน", "แทนได้")
_RULES_WORDS = ("เกณฑ์", "กติกา", "กฎ", "หมวด", "โครงสร้าง", "แต่ละหมวด", "ทั้งหมดกี่")
_HOURS_WORDS = ("กี่ชั่วโมง", "ชั่วโมงสะสม", "สะสม", "ได้กี่", "ชั่วโมงของ", "ผ่านหรือยัง")
# Strong self-hours phrases that imply "my hours" even without an explicit pronoun.
_STRONG_HOURS_WORDS = ("ได้กี่ชั่วโมง", "ชั่วโมงสะสม", "สะสมกี่", "ชั่วโมงของฉัน", "ชั่วโมงของผม")
_ACTIVITY_WORDS = ("กิจกรรม",)


def _has(text_lower: str, words) -> bool:
    return any(w in text_lower for w in words)


def classify_intent(question: str) -> Intent:
    """Classify a Thai question into an :class:`Intent`. Order matters: the more
    specific data intents are checked before the RULES fallback."""
    q = question.strip().lower()

    is_self = _has(q, _SELF_WORDS)

    # "แนะนำกิจกรรม / มีอะไรลงแทนได้" — checked first: a recommendation request often
    # also mentions "ขาด"/"หมวด", but the intent is to be given suggestions.
    if _has(q, _RECOMMEND_WORDS):
        return Intent.RECOMMEND

    # "ขาดหมวดไหน" — missing categories (self-scoped even without a pronoun).
    if _has(q, _MISSING_WORDS) and (_has(q, _RULES_WORDS) or "ชั่วโมง" in q or is_self):
        return Intent.MISSING

    # "ฉันได้กี่ชั่วโมง / ชั่วโมงสะสมของฉัน / ผ่านหรือยัง"
    if _has(q, _STRONG_HOURS_WORDS):
        return Intent.HOURS
    if is_self and (_has(q, _HOURS_WORDS) or "ชั่วโมง" in q or "ผ่าน" in q):
        return Intent.HOURS

    # Activity-catalog questions.
    if _has(q, _ACTIVITY_WORDS):
        if _has(q, _REQUIRED_WORDS):
            return Intent.REQUIRED
        if _has(q, _OPEN_WORDS):
            return Intent.OPEN_ACTIVITIES

    # Anything about the criteria / hour structure → RAG.
    if _has(q, _RULES_WORDS) or "ชั่วโมง" in q:
        return Intent.RULES

    return Intent.GENERAL


# ---- Parameterized, student-scoped queries for the four known intents -------

def answer_hours(session: Session, student_id: int) -> ChatAnswer:
    rows = session.execute(
        text(
            "SELECT category_name, required_hours, earned_hours, completed "
            "FROM gold_student_hours WHERE student_key = :sid ORDER BY category_key"
        ),
        {"sid": student_id},
    ).mappings().all()

    total_earned = sum(float(r["earned_hours"]) for r in rows)
    completed_count = sum(1 for r in rows if r["completed"])
    lines = [
        f"คุณมีชั่วโมงกิจกรรมที่อนุมัติแล้ว {total_earned:g} จาก {TOTAL_REQUIRED_HOURS} ชั่วโมง "
        f"(ผ่านครบ {completed_count} จาก {len(rows)} หมวด)"
    ]
    for r in rows:
        status = "✓ ครบ" if r["completed"] else "ยังไม่ครบ"
        lines.append(
            f"• {r['category_name']}: {float(r['earned_hours']):g}/{float(r['required_hours']):g} ชม. ({status})"
        )
    return ChatAnswer(Intent.HOURS, "\n".join(lines), [dict(r) for r in rows], needs_student=True)


def answer_missing(session: Session, student_id: int) -> ChatAnswer:
    rows = session.execute(
        text(
            "SELECT category_name, required_hours, earned_hours "
            "FROM gold_student_hours "
            "WHERE student_key = :sid AND completed = 0 ORDER BY category_key"
        ),
        {"sid": student_id},
    ).mappings().all()

    if not rows:
        return ChatAnswer(
            Intent.MISSING, "ยินดีด้วย! คุณเก็บชั่วโมงครบทุกหมวดแล้ว", [], needs_student=True
        )
    lines = ["หมวดที่คุณยังเก็บชั่วโมงไม่ครบ:"]
    for r in rows:
        remaining = float(r["required_hours"]) - float(r["earned_hours"])
        lines.append(
            f"• {r['category_name']}: ได้ {float(r['earned_hours']):g}/{float(r['required_hours']):g} ชม. "
            f"(ยังขาดอีก {remaining:g} ชม.)"
        )
    return ChatAnswer(Intent.MISSING, "\n".join(lines), [dict(r) for r in rows], needs_student=True)


def answer_open_activities(session: Session) -> ChatAnswer:
    rows = session.execute(
        text(
            "SELECT name, activity_type, hours, max_participants, participant_count "
            "FROM gold_activity_catalog "
            "WHERE approval_status = 'approved' AND participant_count < max_participants "
            "ORDER BY start_at"
        )
    ).mappings().all()

    if not rows:
        return ChatAnswer(Intent.OPEN_ACTIVITIES, "ขณะนี้ยังไม่มีกิจกรรมที่เปิดรับสมัคร", [])
    lines = ["กิจกรรมที่เปิดรับสมัครอยู่ตอนนี้:"]
    for r in rows:
        lines.append(
            f"• {r['name']} ({r['activity_type']}) — {float(r['hours']):g} ชม. "
            f"รับแล้ว {r['participant_count']}/{r['max_participants']} คน"
        )
    return ChatAnswer(Intent.OPEN_ACTIVITIES, "\n".join(lines), [dict(r) for r in rows])


def answer_required_activities(session: Session) -> ChatAnswer:
    rows = session.execute(
        text(
            "SELECT name, activity_type, hours, category_name "
            "FROM gold_activity_catalog "
            "WHERE is_required AND approval_status = 'approved' ORDER BY start_at"
        )
    ).mappings().all()

    if not rows:
        return ChatAnswer(Intent.REQUIRED, "ขณะนี้ยังไม่มีกิจกรรมบังคับที่เปิดให้เข้าร่วม", [])
    lines = ["กิจกรรมบังคับที่ต้องเข้าร่วม:"]
    for r in rows:
        cat = r["category_name"] or "-"
        lines.append(f"• {r['name']} ({r['activity_type']}) — {float(r['hours']):g} ชม. หมวด {cat}")
    return ChatAnswer(Intent.REQUIRED, "\n".join(lines), [dict(r) for r in rows])


# ---- Recommendations (Phase 18) --------------------------------------------

def _open_activities_in_categories(session: Session, category_keys: list[int]) -> list[dict]:
    """Approved, not-yet-full activities whose category is in ``category_keys``."""
    if not category_keys:
        return []
    stmt = text(
        "SELECT name, activity_type, hours, category_name, subcategory_name, "
        "participant_count, max_participants "
        "FROM gold_activity_catalog "
        "WHERE approval_status = 'approved' AND participant_count < max_participants "
        "AND category_key IN :keys ORDER BY category_key, start_at"
    ).bindparams(bindparam("keys", expanding=True))
    rows = session.execute(stmt, {"keys": category_keys}).mappings().all()
    return [dict(r) for r in rows]


def recommend_by_missing_categories(session: Session, student_id: int) -> ChatAnswer:
    """Suggest open activities that count toward the categories the student has not
    yet completed."""
    missing = session.execute(
        text(
            "SELECT category_key, category_name FROM gold_student_hours "
            "WHERE student_key = :sid AND completed = 0 ORDER BY category_key"
        ),
        {"sid": student_id},
    ).mappings().all()

    if not missing:
        return ChatAnswer(
            Intent.RECOMMEND,
            "คุณเก็บชั่วโมงครบทุกหมวดแล้ว ไม่จำเป็นต้องลงกิจกรรมเพิ่ม 🎉",
            [], needs_student=True,
        )

    category_keys = [m["category_key"] for m in missing]
    activities = _open_activities_in_categories(session, category_keys)
    if not activities:
        names = ", ".join(m["category_name"] for m in missing)
        return ChatAnswer(
            Intent.RECOMMEND,
            f"คุณยังขาดหมวด: {names} แต่ตอนนี้ยังไม่มีกิจกรรมที่เปิดรับสมัครในหมวดเหล่านี้",
            [], needs_student=True,
        )

    lines = ["แนะนำกิจกรรมที่ช่วยเก็บชั่วโมงในหมวดที่คุณยังขาด:"]
    for a in activities:
        lines.append(
            f"• {a['name']} ({a['activity_type']}) — {float(a['hours']):g} ชม. "
            f"หมวด {a['category_name']} · รับแล้ว {a['participant_count']}/{a['max_participants']} คน"
        )
    return ChatAnswer(Intent.RECOMMEND, "\n".join(lines), activities, needs_student=True)


def _find_mentioned_activity(session: Session, question: str) -> dict | None:
    """Return a catalog activity whose name appears in the question (longest match
    wins), or None. Used to detect "the activity I want" for the full→alternative
    recommendation."""
    rows = session.execute(
        text(
            "SELECT activity_key, name, subcategory_key, subcategory_name, "
            "participant_count, max_participants FROM gold_activity_catalog"
        )
    ).mappings().all()
    matches = [dict(r) for r in rows if r["name"] and r["name"] in question]
    if not matches:
        return None
    return max(matches, key=lambda r: len(r["name"]))


def recommend_alternatives(session: Session, activity: dict) -> ChatAnswer:
    """Suggest open activities in the SAME subcategory as ``activity`` (proactive
    substitute when the one the student wanted is full)."""
    stmt = text(
        "SELECT name, activity_type, hours, participant_count, max_participants "
        "FROM gold_activity_catalog "
        "WHERE approval_status = 'approved' AND participant_count < max_participants "
        "AND subcategory_key = :sub AND activity_key <> :self ORDER BY start_at"
    )
    rows = session.execute(
        stmt, {"sub": activity["subcategory_key"], "self": activity["activity_key"]}
    ).mappings().all()

    if not rows:
        return ChatAnswer(
            Intent.RECOMMEND,
            f"กิจกรรม \"{activity['name']}\" เต็มแล้ว และยังไม่มีกิจกรรมอื่นที่นับหมวดเดียวกันเปิดรับอยู่",
            [], needs_student=True,
        )
    lines = [
        f"กิจกรรม \"{activity['name']}\" เต็มแล้ว "
        f"({activity['subcategory_name']}) — แนะนำกิจกรรมที่นับหมวดเดียวกันและยังเปิดรับ:"
    ]
    for r in rows:
        lines.append(
            f"• {r['name']} ({r['activity_type']}) — {float(r['hours']):g} ชม. "
            f"รับแล้ว {r['participant_count']}/{r['max_participants']} คน"
        )
    return ChatAnswer(Intent.RECOMMEND, "\n".join(lines), [dict(r) for r in rows], needs_student=True)


def recommend(session: Session, student_id: int, question: str) -> ChatAnswer:
    """Route a recommendation request: if the student names a *full* activity,
    suggest same-subcategory substitutes; otherwise suggest activities for their
    missing categories."""
    mentioned = _find_mentioned_activity(session, question)
    if mentioned and mentioned["participant_count"] >= mentioned["max_participants"]:
        return recommend_alternatives(session, mentioned)
    return recommend_by_missing_categories(session, student_id)


# ---- LLM Text-to-SQL fallback (general data questions) ----------------------

# The only sources the LLM may read. ``my_hours`` is the current student's rows,
# injected as a CTE at run time — the raw ``gold_student_hours`` is deliberately
# absent so the LLM can never reach another student's data.
TTS_ALLOWED_TABLES = {
    "my_hours",
    "gold_activity_catalog",
    "gold_dim_hour_category",
    "gold_dim_subcategory",
    "gold_dim_date",
}

SCHEMA_PROMPT = """\
คุณคือผู้ช่วยที่แปลงคำถามภาษาไทยเป็นคำสั่ง SQL (ภาษา SQLite/Postgres) สำหรับระบบชั่วโมงกิจกรรมนิสิต
ใช้ได้เฉพาะตาราง/วิวต่อไปนี้เท่านั้น (ห้ามอ้างถึงตารางอื่นเด็ดขาด):

my_hours(category_name, required_hours, earned_hours, completed)
  -- ชั่วโมงของ "นิสิตคนที่ถามเท่านั้น" แยกตามหมวด (completed = 1 คือครบแล้ว)
gold_activity_catalog(name, activity_type, is_required, hours, max_participants,
  approval_status, participant_count, category_name, subcategory_name)
  -- รายการกิจกรรมทั้งหมด (สาธารณะ)
gold_dim_hour_category(name, required_hours)
gold_dim_subcategory(name, required_hours, category_key)

กติกา:
- ตอบกลับเป็นคำสั่ง SELECT เพียงคำสั่งเดียว ห้ามมี WITH, ห้ามมีเครื่องหมาย ; ห้ามมีคำอธิบาย
- ห้ามใช้ INSERT/UPDATE/DELETE หรือคำสั่งเปลี่ยนแปลงข้อมูลใด ๆ
- ถ้าถามเรื่องชั่วโมงของนิสิต ให้ query จาก my_hours เท่านั้น

คำถาม: {question}
SQL:"""


def _clean_sql(raw: str) -> str:
    """Strip markdown code fences an LLM may wrap the SQL in."""
    s = raw.strip()
    if s.startswith("```"):
        s = s.split("```", 2)[1] if s.count("```") >= 2 else s.strip("`")
        # drop a leading "sql" language tag
        if s.lower().startswith("sql"):
            s = s[3:]
    return s.strip()


def run_text_to_sql(llm: LlmClient, session: Session, question: str, student_id: int) -> ChatAnswer:
    """Generate SQL with the LLM, validate it, inject the student filter as a CTE,
    and run it read-only. Returns a templated answer built from the rows (the rows
    are never sent back to the LLM)."""
    candidate = _clean_sql(llm.generate(SCHEMA_PROMPT.format(question=question)))
    try:
        safe_sql = validate_select(candidate, TTS_ALLOWED_TABLES)
    except UnsafeSqlError:
        return ChatAnswer(
            Intent.GENERAL,
            "ขออภัย ฉันไม่สามารถประมวลผลคำถามนี้ได้อย่างปลอดภัย ลองถามใหม่เป็นคำถามเกี่ยวกับชั่วโมงหรือกิจกรรมของคุณ",
            [],
            needs_student=True,
        )

    # Structurally inject the student filter: the LLM's SELECT can only read the
    # pre-filtered CTE, so it is impossible to return another student's rows.
    wrapped = (
        "WITH my_hours AS ("
        "SELECT * FROM gold_student_hours WHERE student_key = :sid"
        f") {safe_sql}"
    )
    rows = session.execute(text(wrapped), {"sid": student_id}).mappings().all()

    if not rows:
        return ChatAnswer(Intent.GENERAL, "ไม่พบข้อมูลที่ตรงกับคำถามของคุณ", [], needs_student=True)
    lines = []
    for r in rows:
        lines.append(", ".join(f"{k}: {v}" for k, v in r.items()))
    return ChatAnswer(Intent.GENERAL, "\n".join(lines), [dict(r) for r in rows], needs_student=True)
