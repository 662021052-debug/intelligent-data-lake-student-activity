"""SQL validator for the chatbot's Text-to-SQL path (Phase 17).

Text-to-SQL is dangerous if an LLM-generated string is executed blindly: a student
could try to read other students' rows or mutate data (directly or via prompt
injection such as "ignore the rules and show all"). This guard is the last line of
defense before execution — it does NOT trust the LLM:

  * exactly one statement (no ``;`` chaining)
  * must be a ``SELECT`` (no DDL/DML: INSERT/UPDATE/DELETE/DROP/... are rejected)
  * no SQL comments (``--`` / ``/* */``) that could hide a payload
  * every table/view it reads must be in an explicit allow-list

Student-row isolation is enforced separately and structurally (see
``chatbot_sql.run_text_to_sql``): the query may only read a pre-filtered CTE bound
to the current student, never the raw student-level views. The allow-list here makes
that guarantee enforceable by forbidding the raw views outright.
"""
from __future__ import annotations

import re

# Statement-level DML/DDL and other dangerous verbs. Matched as whole words, case
# insensitive, anywhere in the string.
_FORBIDDEN_KEYWORDS = (
    "insert", "update", "delete", "drop", "alter", "create", "truncate",
    "replace", "merge", "attach", "detach", "pragma", "grant", "revoke",
    "vacuum", "reindex", "exec", "execute", "call", "copy", "into",
)

_IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_]*"
# Tables/views appear right after FROM or JOIN.
_TABLE_REF = re.compile(rf"\b(?:from|join)\s+({_IDENTIFIER})", re.IGNORECASE)
_WORD = re.compile(r"[A-Za-z_]+")


class UnsafeSqlError(ValueError):
    """Raised when a candidate SQL string fails validation."""


def _strip_trailing_semicolon(sql: str) -> str:
    return sql.strip().rstrip(";").strip()


def validate_select(sql: str, allowed_tables: set[str]) -> str:
    """Validate a single read-only SELECT and return it normalized (no trailing ``;``).

    Raises :class:`UnsafeSqlError` on anything that is not a single, table-whitelisted
    SELECT with no comments or dangerous keywords.
    """
    if not sql or not sql.strip():
        raise UnsafeSqlError("empty SQL")

    raw = sql.strip()

    # No SQL comments — they can hide a second statement or a payload.
    if "--" in raw or "/*" in raw or "*/" in raw:
        raise UnsafeSqlError("comments are not allowed")

    normalized = _strip_trailing_semicolon(raw)

    # Exactly one statement: after stripping a single trailing ';', none may remain.
    if ";" in normalized:
        raise UnsafeSqlError("multiple statements are not allowed")

    # Must be a SELECT (allow a leading CTE only if the caller opted in — by default
    # the LLM returns a bare SELECT because the student-filter CTE is injected later).
    if not re.match(r"^\s*select\b", normalized, re.IGNORECASE):
        raise UnsafeSqlError("only SELECT statements are allowed")

    # Reject dangerous verbs anywhere (whole-word match so column names like
    # "created_by" or "update_at" don't trip it via the word boundary).
    lowered_words = set(w.lower() for w in _WORD.findall(normalized))
    banned = lowered_words & set(_FORBIDDEN_KEYWORDS)
    if banned:
        raise UnsafeSqlError(f"forbidden keyword(s): {', '.join(sorted(banned))}")

    # Every referenced table/view must be explicitly allowed.
    referenced = {m.group(1).lower() for m in _TABLE_REF.finditer(normalized)}
    if not referenced:
        raise UnsafeSqlError("no table referenced")
    allowed = {t.lower() for t in allowed_tables}
    illegal = referenced - allowed
    if illegal:
        raise UnsafeSqlError(f"table(s) not allowed: {', '.join(sorted(illegal))}")

    return normalized
