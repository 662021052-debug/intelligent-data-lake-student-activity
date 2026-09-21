"""ส่งออกรายงานชั่วโมงกิจกรรมสะสมเป็น Excel / PDF (ข้อ 6.5).

ข้อมูลอ่านจาก ``gold_student_hours`` (Gold Layer) เท่านั้น เหมือนแดชบอร์ด —
ตัวเลขในไฟล์ที่ส่งออกจึงตรงกับตัวเลขบนหน้าจอเสมอ ไม่ใช่คนละชุดเพราะคำนวณคนละที่

รายงานมี 2 รูปแบบ:

* **ละเอียด** — หนึ่งแถว = นิสิตหนึ่งคน × หมวดหนึ่งหมวด (grain เดียวกับ view ต้นทาง) แถว
  "สถานะ" จึงเป็นสถานะของหมวดนั้น ไม่ใช่ของนิสิตทั้งคน (Excel ใช้รูปแบบนี้เสมอ)
* **สรุปต่อคน** — หนึ่งแถว = นิสิตหนึ่งคน (ค่าเริ่มต้นของ PDF) ชั่วโมงรวม + จำนวนหมวดที่ครบ
  + สถานะรวม (ครบก็ต่อเมื่อครบทุกหมวด — กติกาเดียวกับแดชบอร์ด)

การจัดหน้า PDF อยู่ที่ ``report_pdf.py`` · ``openpyxl`` และ ``reportlab`` ถูก import แบบ lazy
ในฟังก์ชันที่ใช้จริง ตามแนวเดียวกับ minio/easyocr — โมดูลนี้ import ได้เสมอ
แม้เครื่องนั้นยังไม่ได้ติดตั้ง
"""

from __future__ import annotations

import io
import math
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, Sequence

from sqlalchemy import text
from sqlmodel import Session

from app.completion import ItemProgress
from app.timeutil import format_thai_datetime, now_th_naive

REPORT_TITLE = "รายงานชั่วโมงกิจกรรมสะสมของนิสิต"

COLUMN_HEADERS = [
    "รหัสนิสิต",
    "ชื่อ-สกุล",
    "คณะ",
    "ชั้นปี",
    "หมวดกิจกรรม",
    "ชั่วโมงที่ได้",
    "ชั่วโมงที่ต้องการ",
    "สถานะ",
]

SUMMARY_COLUMN_HEADERS = [
    "รหัสนิสิต",
    "ชื่อ-สกุล",
    "คณะ",
    "ชั้นปี",
    "ชั่วโมงที่ได้",
    "หมวดที่ครบ",
    "สถานะ",
]

STATUS_COMPLETE = "ครบ"
STATUS_INCOMPLETE = "ไม่ครบ"

MODE_SUMMARY = "summary"
MODE_DETAIL = "detail"

# เกินนี้ (จำนวนแถวของรูปแบบที่เลือก) หน้าเว็บจะเตือนก่อนออกไฟล์ — 5,000 แถว ≈ 200 หน้า
LARGE_REPORT_ROWS = 5000
# แถวต่อหน้าโดยประมาณของ PDF (A4 แนวนอน) ไว้ประมาณจำนวนหน้าตอนเตือน — ตรวจกับไฟล์จริงในเทสต์
PDF_ROWS_PER_PAGE = 24

SEMESTER_LABELS = {1: "ภาคเรียนที่ 1", 2: "ภาคเรียนที่ 2", 3: "ภาคฤดูร้อน"}

XLSX_MEDIA_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
PDF_MEDIA_TYPE = "application/pdf"


class ThaiFontMissingError(RuntimeError):
    """เครื่องนี้ไม่มีฟอนต์ไทย จึงสร้าง PDF ที่อ่านออกไม่ได้

    ตั้งใจให้ล้มเสียงดังแทนการปล่อยไฟล์ที่ตัวอักษรไทยกลายเป็นกล่องสี่เหลี่ยมออกไป
    — ผู้ใช้จะไม่รู้เลยว่าไฟล์เสียจนกว่าจะเปิดดู (Excel ไม่มีปัญหานี้ ฟอนต์อยู่ที่
    เครื่องคนเปิด)
    """


@dataclass(frozen=True)
class ReportRow:
    student_code: str
    full_name: str
    faculty: str
    year_level: int
    category_name: str
    earned_hours: float
    required_hours: float
    completed: bool
    student_key: int = 0  # ไว้รวมเป็นรายคน (ไม่แสดงในไฟล์)

    @property
    def status_text(self) -> str:
        return STATUS_COMPLETE if self.completed else STATUS_INCOMPLETE


@dataclass(frozen=True)
class StudentSummary:
    """หนึ่งแถวของรายงาน "สรุปต่อคน" """

    student_code: str
    full_name: str
    faculty: str
    year_level: int
    total_hours: float  # ชั่วโมงอนุมัติรวมของนิสิต (นับกิจกรรมละครั้ง ไม่ซ้ำตามหมวด)
    completed_items: int
    total_items: int

    @property
    def all_completed(self) -> bool:
        return self.total_items > 0 and self.completed_items == self.total_items

    @property
    def status_text(self) -> str:
        return STATUS_COMPLETE if self.all_completed else STATUS_INCOMPLETE

    @property
    def items_text(self) -> str:
        return f"ครบ {self.completed_items}/{self.total_items} หมวด"


def _format_hours(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f"{value:g}"


def _student_clauses(faculty: Optional[str], year_level: Optional[int]) -> tuple[list[str], dict]:
    clauses = ["1 = 1"]
    params: dict = {}
    if faculty:
        clauses.append("faculty = :faculty")
        params["faculty"] = faculty
    if year_level is not None:
        clauses.append("year_level = :year_level")
        params["year_level"] = year_level
    return clauses, params


def fetch_report_rows(
    session: Session,
    *,
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
) -> list[ReportRow]:
    """แถวของรายงานตามตัวกรอง เรียงตามรหัสนิสิต แล้วตามลำดับหมวด

    ไม่กรองภาคเรียน = ยอดสะสมทั้งหลักสูตรจาก gold_student_hours ตรง ๆ · กรองภาคเรียน = คำนวณ
    ชั่วโมงที่ได้ของแต่ละหมวดใหม่จากการเข้าร่วมในภาคนั้นเท่านั้น (วิธีเดียวกับแดชบอร์ด) ส่วน
    "ชั่วโมงที่ต้องการ" ยังเป็นของทั้งหลักสูตร และสถานะเทียบสองค่านั้นด้วยกฎเดียวกับแดชบอร์ด
    """
    clauses, params = _student_clauses(faculty, year_level)
    rows = session.execute(
        text(
            "SELECT student_code, full_name, faculty, year_level, category_name, "
            "earned_hours, required_hours, completed, student_key, category_key "
            "FROM gold_student_hours "
            f"WHERE {' AND '.join(clauses)} "
            "ORDER BY student_code, category_key"
        ),
        params,
    ).all()

    semester_earned: dict[tuple[int, int], float] = {}
    if semester is not None:
        semester_earned = {
            (student_key, item_key): float(hours or 0)
            for student_key, item_key, hours in session.execute(
                text(
                    "SELECT f.student_key, f.item_key, SUM(f.hours_earned) "
                    "FROM gold_fact_item_hours f "
                    "JOIN gold_dim_date d ON d.date_key = f.date_key "
                    "WHERE d.semester = :semester GROUP BY f.student_key, f.item_key"
                ),
                {"semester": semester},
            ).all()
        }

    result = []
    for code, name, fac, year, category, earned, required, completed, student_key, item_key in rows:
        if semester is not None:
            earned = semester_earned.get((student_key, item_key), 0.0)
            completed = ItemProgress(item_key, "", float(earned), float(required or 0)).completed
        result.append(
            ReportRow(
                student_code=str(code),
                full_name=str(name),
                faculty=str(fac),
                year_level=int(year),
                category_name=str(category or "ไม่ระบุหมวด"),
                earned_hours=float(earned or 0),
                required_hours=float(required or 0),
                completed=bool(completed),
                student_key=int(student_key),
            )
        )
    return result


def fetch_student_totals(session: Session, *, semester: Optional[int] = None) -> dict[int, float]:
    """student_key → ชั่วโมงอนุมัติรวม (กิจกรรมละครั้ง) — ตัวเลขเดียวกับ "ชั่วโมงรวม" บนแดชบอร์ด

    ไม่ใช้ผลรวมของแถวรายหมวด เพราะกิจกรรมหนึ่งนับเข้าได้หลายรายการเกณฑ์ (เต็มชั่วโมงทุกรายการ)
    ผลรวมรายหมวดจึงนับซ้ำ
    """
    sql = "SELECT f.student_key, SUM(f.hours_earned) FROM gold_fact_participation f"
    params: dict = {}
    if semester is not None:
        sql += " JOIN gold_dim_date d ON d.date_key = f.date_key WHERE d.semester = :semester"
        params["semester"] = semester
    sql += " GROUP BY f.student_key"
    return {row[0]: float(row[1] or 0) for row in session.execute(text(sql), params).all()}


def summarize_rows(rows: Sequence[ReportRow], totals: dict[int, float]) -> list[StudentSummary]:
    """รวมแถวรายหมวดเป็นแถวเดียวต่อนิสิต (คงลำดับตามรหัสนิสิตเดิม)"""
    grouped: dict[str, list[ReportRow]] = {}
    for row in rows:
        grouped.setdefault(row.student_code, []).append(row)
    return [
        StudentSummary(
            student_code=code,
            full_name=items[0].full_name,
            faculty=items[0].faculty,
            year_level=items[0].year_level,
            total_hours=totals.get(items[0].student_key, 0.0),
            completed_items=sum(1 for item in items if item.completed),
            total_items=len(items),
        )
        for code, items in grouped.items()
    ]


def fetch_report_summary(
    session: Session,
    *,
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
) -> list[StudentSummary]:
    rows = fetch_report_rows(session, faculty=faculty, year_level=year_level, semester=semester)
    return summarize_rows(rows, fetch_student_totals(session, semester=semester))


def count_report_rows(
    session: Session, *, faculty: Optional[str] = None, year_level: Optional[int] = None
) -> tuple[int, int]:
    """(จำนวนนิสิต, จำนวนแถวแบบละเอียด) ตามตัวกรอง — ภาคเรียนไม่เปลี่ยนจำนวนแถว จึงไม่รับ

    ไว้เตือนผู้ใช้ก่อนออกไฟล์ใหญ่ โดยไม่ต้องดึงแถวทั้งหมดมานับ
    """
    clauses, params = _student_clauses(faculty, year_level)
    students, detail_rows = session.execute(
        text(
            "SELECT COUNT(DISTINCT student_key), COUNT(*) FROM gold_student_hours "
            f"WHERE {' AND '.join(clauses)}"
        ),
        params,
    ).one()
    return int(students or 0), int(detail_rows or 0)


def estimate_pdf_pages(rows: int) -> int:
    return max(1, math.ceil(rows / PDF_ROWS_PER_PAGE))


def describe_filters(
    faculty: Optional[str], year_level: Optional[int], semester: Optional[int] = None
) -> str:
    """บรรทัดบอกเงื่อนไขที่ใช้กรอง เขียนบนหัวรายงานเพื่อไม่ให้ไฟล์ที่พิมพ์ออกมา
    กำกวมว่าเป็นข้อมูลของใครบ้าง"""
    parts = []
    if faculty:
        # ชื่อจริงในระบบขึ้นต้นด้วย "คณะ"/"วิทยาลัย" อยู่แล้ว — เติมซ้ำจะได้ "คณะคณะ..."
        parts.append(faculty if faculty.startswith(("คณะ", "วิทยาลัย")) else f"คณะ{faculty}")
    if year_level is not None:
        parts.append(f"ชั้นปีที่ {year_level}")
    note = " · ".join(parts) if parts else "ทุกคณะ ทุกชั้นปี"
    if semester is not None:
        # ต้องบอกให้ชัด: ผู้อ่านมักคิดว่า "ชั่วโมงที่ต้องการ" ถูกหารตามภาคด้วย
        note += (
            f" · {SEMESTER_LABELS.get(semester, f'ภาคเรียนที่ {semester}')} "
            "(นับชั่วโมงที่ได้เฉพาะภาคเรียนนี้ เทียบกับชั่วโมงที่ต้องการของทั้งหลักสูตร)"
        )
    return note


def report_filename(extension: str, now: Optional[datetime] = None) -> str:
    """ชื่อไฟล์ภาษาไทยพร้อมวันที่ เช่น `รายงานชั่วโมงกิจกรรม_2026-08-05.xlsx`"""
    stamp = (now or now_th_naive()).strftime("%Y-%m-%d")
    return f"รายงานชั่วโมงกิจกรรม_{stamp}.{extension}"


# --------------------------- Excel ---------------------------
def build_xlsx(rows: list[ReportRow], *, filter_note: str, generated_at: Optional[datetime] = None) -> bytes:
    from openpyxl import Workbook  # lazy
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "ชั่วโมงกิจกรรม"

    sheet.append([REPORT_TITLE])
    sheet["A1"].font = Font(size=14, bold=True)
    sheet.append([f"เงื่อนไข: {filter_note}"])
    sheet.append([f"ออกรายงานเมื่อ {format_thai_datetime(generated_at or now_th_naive())}"])
    sheet.append([])

    header_row = sheet.max_row + 1
    sheet.append(COLUMN_HEADERS)
    header_fill = PatternFill("solid", start_color="FFE8EAF6")
    for column in range(1, len(COLUMN_HEADERS) + 1):
        cell = sheet.cell(row=header_row, column=column)
        cell.font = Font(bold=True)
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center")

    for row in rows:
        sheet.append(
            [
                row.student_code,
                row.full_name,
                row.faculty,
                row.year_level,
                row.category_name,
                row.earned_hours,
                row.required_hours,
                row.status_text,
            ]
        )

    # ตรึงหัวตารางไว้ + ตัวกรองในตัว เพื่อให้ไฟล์ที่มีหลายร้อยแถวยังใช้งานได้จริง
    sheet.freeze_panes = sheet.cell(row=header_row + 1, column=1)
    sheet.auto_filter.ref = (
        f"A{header_row}:{get_column_letter(len(COLUMN_HEADERS))}{header_row + len(rows)}"
    )
    for index, width in enumerate([14, 28, 22, 8, 26, 14, 18, 10], start=1):
        sheet.column_dimensions[get_column_letter(index)].width = width

    buffer = io.BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()
