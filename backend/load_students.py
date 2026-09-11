"""เฟส 3 ของการรื้อ DB: นำเข้านิสิตจริงจากไฟล์ Excel พร้อมบัญชีเข้าใช้งาน

อ่านไฟล์รายชื่อ (คอลัมน์: รหัสนิสิต · ชื่อ - สกุล · คณะ · สถานะ) แล้วสร้าง
``student`` + ``user`` (role=student) ให้ทุกแถว:

- ``cohort`` ถอดจากรหัสนิสิต 2 หลักแรก · ``criteria_set_id`` ตามกฎ §8
  (เข้า ≥ 2567 → 2567-regular · ≤ 2566 → legacy) · ``program_type`` = regular
- ``year_level`` คำนวณจากรุ่นเทียบกับปีการศึกษาปัจจุบัน — ไฟล์ไม่มีคอลัมน์นี้ แต่ตาราง
  บังคับ NOT NULL และแดชบอร์ดแยกตามชั้นปี
- ``major`` = "ไม่ระบุ" — ไฟล์ไม่มีสาขา แต่ตารางและแอปฝั่งหน้าจอบังคับว่าต้องมีค่า
- ``imported_completion`` เก็บ "สถานะ" ผ่าน/ไม่ผ่าน ไว้ใช้สร้างการเข้าร่วมจำลองในเฟสถัดไป

**ทั้งไฟล์หรือไม่เลย**: ถ้ามีแถวไหนผิดรูป (รหัสไม่ใช่ตัวเลข 9–10 หลัก · รหัสซ้ำ · สถานะ
ไม่รู้จัก) จะรายงานทุกแถวที่ผิดแล้วหยุด ไม่เขียนอะไรลงฐานเลย — นำเข้าครึ่ง ๆ กลาง ๆ
แล้วมาไล่หาว่าใครเข้าไม่ครบนั้นแย่กว่ามาก

**รันซ้ำได้**: นิสิตที่มีอยู่แล้วจะถูกอัปเดตชื่อ/คณะ/รุ่น/สถานะตามไฟล์ แต่ **ไม่รีเซ็ต
รหัสผ่าน** ของบัญชีที่มีอยู่แล้ว (ไม่งั้นนิสิตที่เปลี่ยนรหัสไปแล้วจะถูกล็อกออก) และไม่แตะ
program_type/criteria_set_id ที่ผู้ดูแลแก้ไว้

ไฟล์ Excel เป็นข้อมูลส่วนบุคคล จึงไม่อยู่ใน image ของคอนเทนเนอร์ — รันจากเครื่องโดยชี้
DATABASE_URL ไปที่ Postgres ของ docker compose:

    DATABASE_URL=postgresql://postgres:postgres@localhost:5432/activity_lake \\
        python load_students.py seed/students_69.xlsx
    python load_students.py seed/students_69.xlsx --dry-run
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import openpyxl
from sqlmodel import Session, select

from app.auth import hash_password
from app.criteria import cohort_from_student_id, criteria_set_code_for
from app.database import create_db_and_tables, engine
from app.models import (
    CriteriaSet,
    ImportedCompletion,
    ProgramType,
    Student,
    StudentStatus,
    User,
    UserRole,
)
from app.timeutil import academic_year_for

# รหัสผ่านเริ่มต้นร่วมกันของบัญชีนิสิตที่สร้างใหม่ — แทนได้ด้วย --password หรือ env
# ใช้ค่าเดียวกับบัญชีนิสิตในชุดเทสต์ (student123) เพื่อให้เดโมจำง่าย
DEFAULT_STUDENT_PASSWORD = "student123"
PASSWORD_ENV = "STUDENT_DEFAULT_PASSWORD"

UNKNOWN_MAJOR = "ไม่ระบุ"

# หัวคอลัมน์ที่ยอมรับ (เทียบหลังตัดช่องว่างทิ้งทั้งหมด — "ชื่อ - สกุล" กับ "ชื่อ-สกุล" จึงเท่ากัน)
_HEADER_ALIASES: dict[str, tuple[str, ...]] = {
    "student_id": ("รหัสนิสิต", "รหัสนักศึกษา"),
    "full_name": ("ชื่อ-สกุล", "ชื่อ-นามสกุล", "ชื่อสกุล"),
    "faculty": ("คณะ",),
    "status": ("สถานะ",),
}

_STATUS_MAP: dict[str, ImportedCompletion] = {
    "ผ่าน": ImportedCompletion.passed,
    "ไม่ผ่าน": ImportedCompletion.failed,
}

_STUDENT_ID_RE = re.compile(r"^\d{9,10}$")


class ImportAborted(Exception):
    """ไฟล์หรือฐานไม่พร้อม — ไม่ได้เขียนอะไรลงฐาน."""


@dataclass(frozen=True)
class StudentRow:
    line: int  # เลขแถวใน Excel (นับหัวตารางเป็นแถว 1) ไว้บอกคนแก้ไฟล์
    student_id: str
    full_name: str
    faculty: str
    completion: ImportedCompletion


@dataclass
class Report:
    students_created: int = 0
    students_updated: int = 0
    students_unchanged: int = 0
    users_created: int = 0
    users_existing: int = 0
    by_criteria_set: dict[str, int] = field(default_factory=dict)
    by_completion: dict[str, int] = field(default_factory=dict)
    by_year_level: dict[int, int] = field(default_factory=dict)
    not_in_file: int = 0


def current_academic_year(today: Optional[date] = None) -> int:
    """ปีการศึกษา (พ.ศ.) ของวันนี้ — กฎอยู่ที่ ``academic_year_for`` ที่เดียว."""
    return academic_year_for(today or date.today())


def year_level_for(cohort: int, academic_year: int) -> int:
    """ชั้นปีจากรุ่น — ขั้นต่ำปี 1 กันกรณีนำเข้าก่อนเปิดภาคของรุ่นใหม่ (ได้ 0 หรือติดลบ)."""
    return max(1, academic_year - cohort + 1)


def _normalize_header(value: object) -> str:
    return re.sub(r"\s+", "", str(value or ""))


def _clean(value: object) -> str:
    """ตัดช่องว่างหัวท้าย และยุบช่องว่างซ้อนในชื่อให้เหลือช่องเดียว."""
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value)).strip()


def _cell_to_student_id(value: object) -> str:
    """Excel อาจเก็บรหัสเป็นตัวเลข (6820510466.0) — แปลงกลับเป็นข้อความโดยไม่ให้มี .0."""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return _clean(value)


def read_rows(path: Path) -> list[StudentRow]:
    """อ่านและตรวจทุกแถว — มีแถวผิดแม้แถวเดียวจะโยน ImportAborted พร้อมรายการทั้งหมด."""
    workbook = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        sheet = workbook.worksheets[0]
        rows = sheet.iter_rows(values_only=True)
        header = next(rows, None)
        if header is None:
            raise ImportAborted("ไฟล์ว่าง ไม่มีหัวตาราง")

        normalized = [_normalize_header(h) for h in header]
        columns: dict[str, int] = {}
        for key, aliases in _HEADER_ALIASES.items():
            for alias in aliases:
                if alias in normalized:
                    columns[key] = normalized.index(alias)
                    break
        missing = [key for key in _HEADER_ALIASES if key not in columns]
        if missing:
            raise ImportAborted(
                f"ไม่พบคอลัมน์ {', '.join(_HEADER_ALIASES[k][0] for k in missing)} "
                f"(หัวตารางที่เจอ: {', '.join(str(h) for h in header if h is not None)})"
            )

        parsed: list[StudentRow] = []
        errors: list[str] = []
        first_line_of: dict[str, int] = {}
        for line, raw in enumerate(rows, start=2):
            if raw is None or all(v is None or str(v).strip() == "" for v in raw):
                continue  # แถวว่างท้ายไฟล์เป็นเรื่องปกติของ Excel

            def cell(key: str) -> object:
                index = columns[key]
                return raw[index] if index < len(raw) else None

            student_id = _cell_to_student_id(cell("student_id"))
            full_name = _clean(cell("full_name"))
            faculty = _clean(cell("faculty"))
            status_text = _clean(cell("status"))

            problems = []
            if not _STUDENT_ID_RE.match(student_id):
                problems.append(f"รหัสนิสิต {student_id!r} ต้องเป็นตัวเลข 9-10 หลัก")
            elif student_id in first_line_of:
                problems.append(f"รหัสนิสิตซ้ำกับแถว {first_line_of[student_id]}")
            if not full_name:
                problems.append("ไม่มีชื่อ-สกุล")
            if not faculty:
                problems.append("ไม่มีคณะ")
            if status_text not in _STATUS_MAP:
                problems.append(f"สถานะ {status_text!r} ไม่รู้จัก (รับ: {', '.join(_STATUS_MAP)})")

            if problems:
                errors.append(f"แถว {line}: {'; '.join(problems)}")
                continue
            first_line_of[student_id] = line
            parsed.append(
                StudentRow(line, student_id, full_name, faculty, _STATUS_MAP[status_text])
            )
    finally:
        workbook.close()

    if errors:
        shown = "\n  ".join(errors[:50])
        more = f"\n  … และอีก {len(errors) - 50} แถว" if len(errors) > 50 else ""
        raise ImportAborted(f"ไฟล์มีแถวผิด {len(errors)} แถว — ไม่ได้นำเข้าเลย:\n  {shown}{more}")
    if not parsed:
        raise ImportAborted("ไฟล์ไม่มีข้อมูลนิสิตสักแถว")
    return parsed


def load(
    session: Session,
    rows: list[StudentRow],
    *,
    password: str,
    academic_year: int,
) -> Report:
    """เขียนนิสิต + บัญชีลง session ที่ให้มา โดยยังไม่ commit (เทสต์เรียกด้วยฐานในหน่วยความจำ)."""
    report = Report()

    criteria_ids = {cs.code: cs.id for cs in session.exec(select(CriteriaSet)).all()}
    needed_codes: dict[str, int] = {}
    for row in rows:
        code = criteria_set_code_for(cohort_from_student_id(row.student_id), ProgramType.regular)
        needed_codes[code] = needed_codes.get(code, 0) + 1
    absent = sorted(code for code in needed_codes if code not in criteria_ids)
    if absent:
        # ปล่อยให้นิสิตเข้าไปแบบ criteria_set_id = NULL จะเงียบ แต่ทั้งระบบคำนวณเกณฑ์ไม่ได้
        raise ImportAborted(
            f"ยังไม่มีชุดเกณฑ์ {', '.join(absent)} ในฐาน — รัน python seed_criteria.py ก่อน"
        )

    existing_students = {s.student_id: s for s in session.exec(select(Student)).all()}
    existing_users = {u.username: u for u in session.exec(select(User)).all()}

    # บัญชีที่ใช้ชื่อเดียวกับรหัสนิสิตแต่เป็นของคนอื่น (staff/admin หรือผูกนิสิตคนอื่น)
    # จะทำให้นิสิตคนนั้นล็อกอินไม่ได้ — ต้องหยุดให้คนตัดสินใจ ไม่ใช่ข้ามไปเงียบ ๆ
    conflicts = []
    for row in rows:
        user = existing_users.get(row.student_id)
        if user is None:
            continue
        student = existing_students.get(row.student_id)
        if user.role != UserRole.student or (student is None or user.student_id != student.id):
            conflicts.append(f"แถว {row.line}: ชื่อผู้ใช้ {row.student_id} เป็นของบัญชีอื่นอยู่แล้ว")
    if conflicts:
        raise ImportAborted("ชื่อผู้ใช้ชนกับบัญชีเดิม — ไม่ได้นำเข้าเลย:\n  " + "\n  ".join(conflicts))

    # bcrypt ช้าโดยตั้งใจ (~0.25 วิ/ครั้ง) — hash ครั้งเดียวแล้วใช้ร่วมกันทุกบัญชี แทนที่จะ
    # hash 2,000 ครั้ง (~8 นาที) รหัสผ่านเหมือนกันอยู่แล้ว hash ที่เหมือนกันจึงไม่เปิดเผยอะไรเพิ่ม
    shared_hash = hash_password(password)

    new_students: dict[str, Student] = {}
    for row in rows:
        cohort = cohort_from_student_id(row.student_id)
        year_level = year_level_for(cohort, academic_year)
        report.by_year_level[year_level] = report.by_year_level.get(year_level, 0) + 1
        report.by_completion[row.completion.value] = (
            report.by_completion.get(row.completion.value, 0) + 1
        )

        student = existing_students.get(row.student_id)
        if student is None:
            code = criteria_set_code_for(cohort, ProgramType.regular)
            student = Student(
                student_id=row.student_id,
                full_name=row.full_name,
                faculty=row.faculty,
                major=UNKNOWN_MAJOR,
                year_level=year_level,
                status=StudentStatus.active,
                cohort=cohort,
                program_type=ProgramType.regular,
                criteria_set_id=criteria_ids[code],
                imported_completion=row.completion,
            )
            session.add(student)
            new_students[row.student_id] = student
            report.students_created += 1
        else:
            updates = {
                "full_name": row.full_name,
                "faculty": row.faculty,
                "cohort": cohort,
                "year_level": year_level,
                "imported_completion": row.completion,
            }
            # ชุดเกณฑ์: เติมให้เฉพาะคนที่ยังว่าง — ถ้าผู้ดูแลตั้งกลุ่ม/ชุดเกณฑ์ไว้แล้วต้องไม่ทับ
            if student.criteria_set_id is None:
                code = criteria_set_code_for(cohort, student.program_type)
                if code in criteria_ids:
                    updates["criteria_set_id"] = criteria_ids[code]
            changed = {k: v for k, v in updates.items() if getattr(student, k) != v}
            for key, value in changed.items():
                setattr(student, key, value)
            if changed:
                session.add(student)
                report.students_updated += 1
            else:
                report.students_unchanged += 1

    # ต้องได้ student.id ก่อนสร้างบัญชีที่ชี้มาหา
    session.flush()

    for row in rows:
        if row.student_id in existing_users:
            report.users_existing += 1
            continue
        student = existing_students.get(row.student_id) or new_students[row.student_id]
        session.add(
            User(
                username=row.student_id,
                hashed_password=shared_hash,
                role=UserRole.student,
                student_id=student.id,
            )
        )
        report.users_created += 1
    session.flush()

    code_by_id = {v: k for k, v in criteria_ids.items()}
    file_ids = {row.student_id for row in rows}
    for student in session.exec(select(Student)).all():
        if student.student_id in file_ids:
            label = code_by_id.get(student.criteria_set_id, "(ไม่มีชุดเกณฑ์)")
            report.by_criteria_set[label] = report.by_criteria_set.get(label, 0) + 1
        else:
            report.not_in_file += 1
    return report


def _print_report(report: Report, academic_year: int, password_source: str) -> None:
    print(
        f"นิสิต: สร้างใหม่ {report.students_created} · อัปเดต {report.students_updated} · "
        f"ไม่เปลี่ยน {report.students_unchanged}"
    )
    print(
        f"บัญชี: สร้างใหม่ {report.users_created} · มีอยู่แล้ว (ไม่แตะรหัสผ่าน) {report.users_existing}"
    )
    print("ชุดเกณฑ์: " + ", ".join(f"{k}={v}" for k, v in sorted(report.by_criteria_set.items())))
    print(
        f"ชั้นปี (ปีการศึกษา {academic_year}): "
        + ", ".join(f"ปี {k}={v}" for k, v in sorted(report.by_year_level.items()))
    )
    print("สถานะตามไฟล์: " + ", ".join(f"{k}={v}" for k, v in sorted(report.by_completion.items())))
    if report.not_in_file:
        print(f"นิสิตในฐานที่ไม่อยู่ในไฟล์ (ไม่ได้แตะ): {report.not_in_file}")
    if report.users_created:
        print(f"รหัสผ่านเริ่มต้นของบัญชีใหม่มาจาก: {password_source}")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="นำเข้านิสิตจากไฟล์ Excel (เฟส 3)")
    parser.add_argument("xlsx", type=Path, help="ไฟล์รายชื่อนิสิต .xlsx")
    parser.add_argument("--dry-run", action="store_true", help="ตรวจและนับอย่างเดียว ไม่เขียนลงฐาน")
    parser.add_argument(
        "--password",
        help=f"รหัสผ่านเริ่มต้นของบัญชีใหม่ (ไม่ใส่ = env {PASSWORD_ENV} หรือค่าเริ่มต้นในโค้ด)",
    )
    parser.add_argument(
        "--academic-year",
        type=int,
        help="ปีการศึกษา (พ.ศ.) สำหรับคำนวณชั้นปี — ไม่ใส่ = คำนวณจากวันนี้",
    )
    args = parser.parse_args(argv)

    if args.password:
        password, password_source = args.password, "--password"
    elif os.environ.get(PASSWORD_ENV):
        password, password_source = os.environ[PASSWORD_ENV], f"env {PASSWORD_ENV}"
    else:
        password, password_source = DEFAULT_STUDENT_PASSWORD, "ค่าเริ่มต้นในโค้ด"
    academic_year = args.academic_year or current_academic_year()

    try:
        rows = read_rows(args.xlsx)
        print(f"อ่านไฟล์ {args.xlsx.name}: {len(rows)} แถว ผ่านการตรวจทั้งหมด")
        create_db_and_tables()
        with Session(engine) as session:
            report = load(session, rows, password=password, academic_year=academic_year)
            if args.dry_run:
                session.rollback()
                print("dry-run — ไม่ได้เขียนอะไรลงฐาน")
            else:
                session.commit()
    except ImportAborted as exc:
        print(f"หยุดการนำเข้า: {exc}")
        return 1

    _print_report(report, academic_year, password_source)
    return 0


if __name__ == "__main__":
    sys.exit(main())
