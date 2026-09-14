"""เฟส 3 ของการรื้อ DB: โหลดรายชื่อนิสิตจริงจากไฟล์ Excel เข้าฐาน

อ่านไฟล์รายชื่อ (คอลัมน์ รหัสนิสิต · ชื่อ - สกุล · คณะ · สถานะ) แล้วสร้างให้ทุกแถว:
- ``student`` — รหัส 10 หลัก ชื่อ คณะ จากไฟล์ · รุ่น/ชุดเกณฑ์ถอดจากรหัสด้วยกฎเดียวกับ
  ที่แอปใช้ (``app/criteria.py``) · program_type = regular · สถานะในไฟล์เก็บที่
  ``student.source_passed`` ไว้ใช้สร้าง participation จำลองในเฟสถัดไป
- ``user`` role=student ผูกกับนิสิตแต่ละคน — username = รหัสนิสิต รหัสผ่านเริ่มต้นเดียวกันหมด

ไฟล์ไม่มีสาขาและชั้นปี แต่สองคอลัมน์นี้เป็น NOT NULL: ชั้นปีคำนวณจากรุ่นเทียบปีการศึกษา
ปัจจุบัน ส่วนสาขาใส่ "ไม่ระบุ" ไว้ให้เห็นชัดว่าไม่มีข้อมูล แทนที่จะเดาจากรหัส

ไม่ได้ต่อเข้า boot ของคอนเทนเนอร์เหมือน seed_criteria.py โดยตั้งใจ: ไฟล์นี้เป็นข้อมูล
ส่วนบุคคลที่ห้าม commit และไม่ถูก COPY เข้า image — เป็นการนำเข้าครั้งเดียวที่คนสั่งเอง
ไม่ใช่นิยามที่ทุกฐานต้องมี

รันซ้ำได้: นิสิตที่มีอยู่แล้วอัปเดตเฉพาะค่าที่มาจากไฟล์ (ชื่อ คณะ สถานะ) · บัญชีที่มีแล้ว
ไม่ถูกรีเซ็ตรหัสผ่าน · นิสิตในฐานที่ไม่อยู่ในไฟล์ไม่ถูกลบ (รายงานจำนวนให้เห็นแทน)

ต้องรัน ``seed_criteria.py`` ก่อน — ถ้ายังไม่มีชุดเกณฑ์ที่นิสิตในไฟล์ต้องใช้ จะหยุดก่อน
เขียนอะไรลงฐาน ไม่ปล่อยให้เกิดนิสิตที่ criteria_set_id ว่างทั้งไฟล์

รัน (Postgres ของ docker compose จากเครื่อง host):
    DATABASE_URL=postgresql://postgres:postgres@localhost:5432/activity_lake \\
        python load_students.py [--file seed/students_69.xlsx] [--password ...] [--dry-run]
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any, Iterable, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from sqlmodel import Session, func, select

from app.auth import hash_password
from app.criteria import (
    academic_year_of,
    cohort_from_student_id,
    criteria_set_code_for,
    year_level_for,
)
from app.models import CriteriaSet, ProgramType, Student, StudentStatus, User, UserRole

DEFAULT_FILE = Path(__file__).resolve().parent / "seed" / "students_69.xlsx"
# รูปแบบเดียวกับบัญชีเดโม admin123/staff123 ใน seed.py
DEFAULT_PASSWORD = "student123"
UNKNOWN_MAJOR = "ไม่ระบุ"

STUDENT_ID_PATTERN = re.compile(r"^\d{10}$")

# หัวคอลัมน์หลังตัดช่องว่างและขีดทิ้ง ("ชื่อ - สกุล" กับ "ชื่อ-สกุล" จึงเป็นคอลัมน์เดียวกัน)
REQUIRED_HEADERS: dict[str, str] = {
    "student_id": "รหัสนิสิต",
    "full_name": "ชื่อสกุล",
    "faculty": "คณะ",
    "status": "สถานะ",
}

STATUS_VALUES: dict[str, bool] = {"ผ่าน": True, "ไม่ผ่าน": False}
STATUS_LABELS: dict[Optional[bool], str] = {True: "ผ่าน", False: "ไม่ผ่าน", None: "ไม่ทราบ"}


class RosterError(Exception):
    """ไฟล์หรือฐานไม่พร้อมให้โหลด — หยุดทั้งงานก่อนเขียนอะไรลงฐาน."""


@dataclass(frozen=True)
class RosterRow:
    row_number: int  # เลขแถวใน Excel (หัวตาราง = แถว 1) ไว้ชี้ตำแหน่งตอนรายงานปัญหา
    student_id: str
    full_name: str
    faculty: str
    passed: Optional[bool]


@dataclass
class Report:
    rows_read: int = 0
    students_created: int = 0
    students_updated: int = 0
    students_unchanged: int = 0
    users_created: int = 0
    by_cohort: Counter = field(default_factory=Counter)
    by_criteria_set: Counter = field(default_factory=Counter)
    by_status: Counter = field(default_factory=Counter)
    by_year_level: Counter = field(default_factory=Counter)
    warnings: list[str] = field(default_factory=list)


def _normalize_header(value: Any) -> str:
    return re.sub(r"[\s\-]", "", str(value or ""))


def _cell_text(value: Any) -> str:
    """ค่าในเซลล์เป็นข้อความ — รหัสที่ Excel เก็บเป็นตัวเลขจะกลายเป็น 6.9e9 ถ้า str() ตรง ๆ."""
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value).strip()


def parse_rows(rows: Iterable[tuple[Any, ...]]) -> tuple[list[RosterRow], list[str]]:
    """แปลงแถวดิบของชีต (แถวแรก = หัวตาราง) เป็น RosterRow + รายการปัญหา

    แถวที่ใช้ไม่ได้ถูกข้ามพร้อมบอกเหตุผล แทนที่จะล้มทั้งไฟล์ — ไฟล์จริงสองพันแถว
    แถวเสียแถวเดียวไม่ควรขวางอีกสองพันคน แต่หัวตารางผิดคือทั้งไฟล์ผิด จึงหยุดทันที
    """
    iterator = iter(rows)
    header = next(iterator, None)
    if header is None:
        raise RosterError("ไฟล์ว่าง — ไม่มีแม้แต่หัวตาราง")

    positions = {_normalize_header(h): i for i, h in enumerate(header)}
    missing = [label for label in REQUIRED_HEADERS.values() if label not in positions]
    if missing:
        raise RosterError(f"ไม่พบคอลัมน์ {', '.join(missing)} ในหัวตาราง: {list(header)}")
    column = {key: positions[label] for key, label in REQUIRED_HEADERS.items()}

    parsed: list[RosterRow] = []
    problems: list[str] = []
    seen: dict[str, int] = {}
    for row_number, raw in enumerate(iterator, start=2):
        cells = {key: _cell_text(raw[i]) if i < len(raw) else "" for key, i in column.items()}
        if not any(cells.values()):
            continue  # แถวว่างท้ายชีต

        student_id = cells["student_id"]
        if not STUDENT_ID_PATTERN.match(student_id):
            problems.append(f"แถว {row_number}: รหัสนิสิต {student_id!r} ไม่ใช่ตัวเลข 10 หลัก — ข้าม")
            continue
        if student_id in seen:
            problems.append(
                f"แถว {row_number}: รหัส {student_id} ซ้ำกับแถว {seen[student_id]} — ใช้แถวแรก"
            )
            continue
        if not cells["full_name"] or not cells["faculty"]:
            problems.append(f"แถว {row_number}: รหัส {student_id} ไม่มีชื่อหรือคณะ — ข้าม")
            continue

        passed = STATUS_VALUES.get(cells["status"])
        if passed is None:
            # ยังโหลดนิสิตคนนี้ตามปกติ แค่ไม่รู้สถานะ — ข้ามทั้งคนเพราะคอลัมน์เดียวไม่คุ้ม
            problems.append(
                f"แถว {row_number}: รหัส {student_id} สถานะ {cells['status']!r} "
                f"ไม่ใช่ ผ่าน/ไม่ผ่าน — โหลดโดยไม่มีสถานะ"
            )

        seen[student_id] = row_number
        parsed.append(
            RosterRow(
                row_number=row_number,
                student_id=student_id,
                full_name=cells["full_name"],
                faculty=cells["faculty"],
                passed=passed,
            )
        )
    return parsed, problems


def read_roster(path: Path) -> tuple[list[RosterRow], list[str]]:
    from openpyxl import load_workbook  # lazy ตามแนวเดียวกับ app/activity_import.py

    if not path.exists():
        raise RosterError(f"ไม่พบไฟล์ {path}")
    workbook = load_workbook(path, read_only=True, data_only=True)
    try:
        # ไฟล์ต้นทางมีชีตเดียว — อ่านชีตแรกเสมอ ไม่ผูกกับชื่อชีตที่ต้นทางเปลี่ยนได้
        return parse_rows(workbook.worksheets[0].iter_rows(values_only=True))
    finally:
        workbook.close()


def load(
    session: Session,
    rows: list[RosterRow],
    *,
    hashed_password: str,
    today: Optional[date] = None,
) -> Report:
    """เขียนนิสิต + บัญชีลง session ที่ให้มา โดยยังไม่ commit

    รับรหัสผ่านที่ hash แล้วเพียงค่าเดียวใช้กับทุกบัญชี: bcrypt ช้าโดยเจตนา (~0.2 วิ/ครั้ง)
    hash ใหม่ทีละคนสองพันครั้งกินหลายนาที ทั้งที่ทุกคนได้รหัสผ่านเดียวกันอยู่แล้ว salt แยก
    รายคนจึงไม่ได้ป้องกันอะไรเพิ่ม — นิสิตเปลี่ยนรหัสผ่านเมื่อไหร่ก็ได้ hash + salt ของตัวเอง
    """
    report = Report(rows_read=len(rows))
    academic_year = academic_year_of(today or date.today())
    program_type = ProgramType.regular

    set_ids = {cs.code: cs.id for cs in session.exec(select(CriteriaSet)).all()}
    planned: list[tuple[RosterRow, Optional[int], str]] = []
    missing_codes: Counter = Counter()
    for row in rows:
        cohort = cohort_from_student_id(row.student_id)
        code = criteria_set_code_for(cohort, program_type)
        if code not in set_ids:
            missing_codes[code] += 1
        planned.append((row, cohort, code))
    if missing_codes:
        detail = ", ".join(f"{code} ({n} คน)" for code, n in sorted(missing_codes.items()))
        raise RosterError(
            f"ยังไม่มีชุดเกณฑ์ {detail} ในฐาน — รัน python seed_criteria.py ก่อน"
        )

    existing = {s.student_id: s for s in session.exec(select(Student)).all()}
    students: list[Student] = []
    for row, cohort, code in planned:
        student = existing.get(row.student_id)
        if student is None:
            student = Student(
                student_id=row.student_id,
                full_name=row.full_name,
                faculty=row.faculty,
                major=UNKNOWN_MAJOR,
                year_level=year_level_for(cohort, academic_year),
                status=StudentStatus.active,
                cohort=cohort,
                program_type=program_type,
                criteria_set_id=set_ids[code],
                source_passed=row.passed,
            )
            session.add(student)
            report.students_created += 1
        else:
            # ไฟล์เป็นเจ้าของ ชื่อ/คณะ/สถานะ จึงทับได้ ส่วนรุ่น/ชุดเกณฑ์เติมเฉพาะที่ว่าง —
            # ผู้ดูแลอาจย้ายนิสิตไปชุดเกณฑ์อื่นด้วยมือ (เช่นกลุ่มต่อเนื่อง) ต้องไม่ถูกดึงกลับ
            changed = False
            for attr, value in (
                ("full_name", row.full_name),
                ("faculty", row.faculty),
                ("source_passed", row.passed),
            ):
                if getattr(student, attr) != value:
                    setattr(student, attr, value)
                    changed = True
            if student.cohort is None:
                student.cohort = cohort
                changed = True
            if student.criteria_set_id is None:
                student.criteria_set_id = set_ids[code]
                changed = True
            if changed:
                session.add(student)
                report.students_updated += 1
            else:
                report.students_unchanged += 1
        students.append(student)

    session.flush()  # ให้ได้ student.id มาผูกบัญชี

    code_by_set_id = {set_id: code for code, set_id in set_ids.items()}
    for student in students:
        report.by_cohort[student.cohort] += 1
        report.by_criteria_set[code_by_set_id.get(student.criteria_set_id)] += 1
        report.by_year_level[student.year_level] += 1
        report.by_status[STATUS_LABELS[student.source_passed]] += 1

    users = session.exec(select(User)).all()
    by_username = {u.username: u for u in users}
    linked_student_ids = {
        u.student_id for u in users if u.role == UserRole.student and u.student_id is not None
    }
    for student in students:
        if student.id in linked_student_ids:
            continue  # มีบัญชีอยู่แล้ว — ไม่แตะ ไม่รีเซ็ตรหัสผ่านที่นิสิตอาจเปลี่ยนไปแล้ว
        taken = by_username.get(student.student_id)
        if taken is not None:
            # เอาบัญชีที่มีอยู่มาผูกเองไม่ได้: อาจเป็น staff/admin หรือบัญชีนิสิตของคนอื่น
            report.warnings.append(
                f"ชื่อผู้ใช้ {student.student_id} ถูกใช้แล้ว (role={taken.role.value}) — "
                f"ไม่ได้สร้างบัญชีให้นิสิตคนนี้"
            )
            continue
        user = User(
            username=student.student_id,
            hashed_password=hashed_password,
            role=UserRole.student,
            student_id=student.id,
        )
        session.add(user)
        by_username[user.username] = user
        report.users_created += 1

    session.flush()
    return report


def _print_report(session: Session, report: Report, parse_problems: list[str]) -> None:
    print(
        f"อ่านได้ {report.rows_read} แถว · นิสิตใหม่ {report.students_created} · "
        f"อัปเดต {report.students_updated} · ไม่เปลี่ยน {report.students_unchanged} · "
        f"บัญชีใหม่ {report.users_created}"
    )
    print(f"  รุ่น (ปีที่เข้า): {dict(sorted(report.by_cohort.items()))}")
    print(f"  ชั้นปี: {dict(sorted(report.by_year_level.items()))}")
    print(f"  ชุดเกณฑ์: {dict(sorted(report.by_criteria_set.items()))}")
    print(f"  สถานะตามไฟล์: {dict(report.by_status)}")

    for line in parse_problems + report.warnings:
        print(f"  ! {line}")

    total_students = session.exec(select(func.count()).select_from(Student)).one()
    outside = total_students - report.rows_read
    if outside:
        print(f"  นิสิตในฐานที่ไม่อยู่ในไฟล์นี้: {outside} คน (ไม่ได้ลบ)")
    linked = select(User.student_id).where(
        User.role == UserRole.student, User.student_id.is_not(None)
    )
    unlinked = session.exec(
        select(func.count()).select_from(Student).where(Student.id.not_in(linked))
    ).one()
    if unlinked:
        print(f"  นิสิตที่ยังไม่มีบัญชีเข้าใช้งาน: {unlinked} คน")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="โหลดรายชื่อนิสิตจากไฟล์ Excel (เฟส 3)")
    parser.add_argument("--file", type=Path, default=DEFAULT_FILE, help="ไฟล์ .xlsx รายชื่อนิสิต")
    parser.add_argument(
        "--password", default=DEFAULT_PASSWORD, help="รหัสผ่านเริ่มต้นของบัญชีนิสิตที่สร้างใหม่"
    )
    parser.add_argument("--dry-run", action="store_true", help="บอกว่าจะเปลี่ยนอะไร ไม่เขียนจริง")
    args = parser.parse_args(argv)

    from app.database import create_db_and_tables, engine

    try:
        rows, problems = read_roster(args.file)
    except RosterError as exc:
        print(f"หยุด: {exc}")
        return 1

    create_db_and_tables()
    with Session(engine) as session:
        try:
            report = load(session, rows, hashed_password=hash_password(args.password))
        except RosterError as exc:
            session.rollback()
            print(f"หยุด: {exc}")
            return 1

        if args.dry_run:
            _print_report(session, report, problems)
            session.rollback()
            print("dry-run — ไม่ได้เขียนอะไรลงฐาน")
            return 0

        session.commit()
        _print_report(session, report, problems)
        shown = "ตามที่ระบุด้วย --password" if args.password != DEFAULT_PASSWORD else args.password
        print(f"ล็อกอินนิสิต: username = รหัสนิสิต, รหัสผ่านเริ่มต้น = {shown}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
