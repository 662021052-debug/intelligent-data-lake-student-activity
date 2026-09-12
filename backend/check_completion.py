"""เฟส 6 ของการรื้อ DB: ตรวจว่าจำนวน "ผ่าน" ที่ระบบคำนวณตรงกับสถานะในไฟล์นำเข้า

เทียบ ``student.imported_completion`` (ผ่าน/ไม่ผ่าน ตามไฟล์ — เฟส 3) กับความครบเกณฑ์ที่ระบบ
คำนวณจาก Gold Layer (``gold_student_hours`` + :mod:`app.completion` — กติกาเดียวกับแดชบอร์ด
และอีเมลกลุ่มเสี่ยง) แล้วพิมพ์ตารางเทียบแยกตามชุดเกณฑ์ พร้อมรายชื่อคนที่ไม่ตรง

สร้าง gold views ใหม่ก่อนตรวจทุกครั้ง (เหมือน ``POST /gold/refresh``) — ไม่ต้องรอแอปบูต

รัน:
    python check_completion.py            # รายงานอย่างเดียว
    python check_completion.py --strict   # exit 1 ถ้ามีคนที่ไม่ตรง (ไว้ใช้ในสคริปต์อัตโนมัติ)
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from dataclasses import dataclass, field
from typing import Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlalchemy import text
from sqlmodel import Session, select

from app.completion import StudentProgress, progress_by_student
from app.database import create_db_and_tables, engine
from app.gold import create_gold_layer
from app.models import CriteriaSet, ImportedCompletion, Student

# แสดงรายชื่อคนที่ไม่ตรงไม่เกินเท่านี้ — ที่เหลือบอกเป็นจำนวน
SHOW_MISMATCHES = 20


@dataclass
class Mismatch:
    student_code: str
    criteria_set: str
    expected: str
    progress: StudentProgress


@dataclass
class Report:
    # (ชุดเกณฑ์, สถานะในไฟล์, ผลที่ระบบคำนวณ) → จำนวนคน
    table: Counter = field(default_factory=Counter)
    mismatches: list[Mismatch] = field(default_factory=list)
    without_status: int = 0

    @property
    def checked(self) -> int:
        return sum(self.table.values())


def compare(session: Session) -> Report:
    rows = session.execute(
        text(
            "SELECT student_key, category_key, category_name, required_hours, earned_hours "
            "FROM gold_student_hours ORDER BY student_key, category_key"
        )
    ).all()
    progress = progress_by_student(tuple(r) for r in rows)
    set_codes = {cs.id: cs.code for cs in session.exec(select(CriteriaSet)).all()}

    report = Report()
    for student in session.exec(select(Student).order_by(Student.student_id)).all():
        if student.imported_completion is None:
            report.without_status += 1
            continue
        p = progress.get(student.id, StudentProgress())
        code = set_codes.get(student.criteria_set_id, "(ไม่มีชุดเกณฑ์)")
        expected = student.imported_completion == ImportedCompletion.passed
        report.table[(code, student.imported_completion.value, "ผ่าน" if p.completed else "ไม่ผ่าน")] += 1
        if p.completed != expected:
            report.mismatches.append(
                Mismatch(student.student_id, code, student.imported_completion.value, p)
            )
    return report


def _print_report(report: Report) -> None:
    print(f"ตรวจนิสิต {report.checked:,} คน (ไม่มีสถานะจากไฟล์ {report.without_status} คน — ไม่ได้ตรวจ)")
    print("\n  ชุดเกณฑ์            สถานะในไฟล์  ระบบคำนวณ   จำนวน")
    for (code, expected, computed), count in sorted(report.table.items()):
        mark = "" if (expected == "passed") == (computed == "ผ่าน") else "  ← ไม่ตรง"
        print(f"  {code:<18} {expected:<11}  {computed:<9} {count:>6,}{mark}")

    if not report.mismatches:
        print("\nผลที่ระบบคำนวณตรงกับสถานะในไฟล์ทุกคน")
        return
    print(f"\nไม่ตรง {len(report.mismatches)} คน:")
    for m in report.mismatches[:SHOW_MISMATCHES]:
        gaps = ", ".join(
            f"{g.name} {g.earned_hours:g}/{g.required_hours:g}" for g in m.progress.gaps
        ) or "ครบทุกรายการ"
        print(
            f"  {m.student_code} [{m.criteria_set}] ไฟล์={m.expected} · "
            f"นับเข้าเกณฑ์ {m.progress.counted_hours:g}/{m.progress.required_hours:g} ชม. · {gaps}"
        )
    if len(report.mismatches) > SHOW_MISMATCHES:
        print(f"  … และอีก {len(report.mismatches) - SHOW_MISMATCHES} คน")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="เทียบความครบเกณฑ์ที่คำนวณกับสถานะในไฟล์ (เฟส 6)")
    parser.add_argument("--strict", action="store_true", help="exit 1 เมื่อมีคนที่ผลไม่ตรง")
    args = parser.parse_args(argv)

    create_db_and_tables()
    with Session(engine) as session:
        create_gold_layer(session)
        report = compare(session)
    _print_report(report)
    return 1 if args.strict and report.mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
