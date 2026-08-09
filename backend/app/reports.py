"""ส่งออกรายงานชั่วโมงกิจกรรมสะสมเป็น Excel / PDF (ข้อ 6.5).

ข้อมูลอ่านจาก ``gold_student_hours`` (Gold Layer) เท่านั้น เหมือนแดชบอร์ด —
ตัวเลขในไฟล์ที่ส่งออกจึงตรงกับตัวเลขบนหน้าจอเสมอ ไม่ใช่คนละชุดเพราะคำนวณคนละที่

หนึ่งแถว = นิสิตหนึ่งคน × หมวดชั่วโมงหนึ่งหมวด (grain เดียวกับ view ต้นทาง) แถว
"สถานะ" จึงเป็นสถานะของหมวดนั้น ไม่ใช่ของนิสิตทั้งคน

``openpyxl`` และ ``reportlab`` ถูก import แบบ lazy ในฟังก์ชันที่ใช้จริง ตามแนวเดียว
กับ minio/easyocr — โมดูลนี้ import ได้เสมอแม้เครื่องนั้นยังไม่ได้ติดตั้ง
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from sqlalchemy import text
from sqlmodel import Session

from app.fonts import find_thai_font
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

STATUS_COMPLETE = "ครบ"
STATUS_INCOMPLETE = "ไม่ครบ"

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

    @property
    def status_text(self) -> str:
        return STATUS_COMPLETE if self.completed else STATUS_INCOMPLETE


def _format_hours(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f"{value:g}"


def fetch_report_rows(
    session: Session,
    *,
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
) -> list[ReportRow]:
    """แถวของรายงานตามตัวกรอง เรียงตามรหัสนิสิต แล้วตามลำดับหมวด"""
    clauses = ["1 = 1"]
    params: dict = {}
    if faculty:
        clauses.append("faculty = :faculty")
        params["faculty"] = faculty
    if year_level is not None:
        clauses.append("year_level = :year_level")
        params["year_level"] = year_level

    rows = session.execute(
        text(
            "SELECT student_code, full_name, faculty, year_level, category_name, "
            "earned_hours, required_hours, completed "
            "FROM gold_student_hours "
            f"WHERE {' AND '.join(clauses)} "
            "ORDER BY student_code, category_key"
        ),
        params,
    ).all()

    return [
        ReportRow(
            student_code=str(code),
            full_name=str(name),
            faculty=str(fac),
            year_level=int(year),
            category_name=str(category or "ไม่ระบุหมวด"),
            earned_hours=float(earned or 0),
            required_hours=float(required or 0),
            completed=bool(completed),
        )
        for code, name, fac, year, category, earned, required, completed in rows
    ]


def describe_filters(faculty: Optional[str], year_level: Optional[int]) -> str:
    """บรรทัดบอกเงื่อนไขที่ใช้กรอง เขียนบนหัวรายงานเพื่อไม่ให้ไฟล์ที่พิมพ์ออกมา
    กำกวมว่าเป็นข้อมูลของใครบ้าง"""
    parts = []
    if faculty:
        parts.append(f"คณะ{faculty}")
    if year_level is not None:
        parts.append(f"ชั้นปีที่ {year_level}")
    return " · ".join(parts) if parts else "ทุกคณะ ทุกชั้นปี"


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


# --------------------------- PDF ---------------------------
_PDF_FONT_NAME = "ThaiReport"


def _register_thai_font() -> str:
    """ลงทะเบียนฟอนต์ไทยกับ reportlab แล้วคืนชื่อฟอนต์ที่ใช้อ้างอิง"""
    from reportlab.pdfbase import pdfmetrics  # lazy
    from reportlab.pdfbase.ttfonts import TTFont

    if _PDF_FONT_NAME in pdfmetrics.getRegisteredFontNames():
        return _PDF_FONT_NAME

    font_path = find_thai_font()
    if font_path is None:
        raise ThaiFontMissingError(
            "ไม่พบฟอนต์ภาษาไทยในเครื่องนี้ จึงสร้างไฟล์ PDF ไม่ได้ "
            "(ติดตั้งแพ็กเกจ fonts-thai-tlwg แล้วลองใหม่ หรือใช้ Excel แทน)"
        )
    pdfmetrics.registerFont(TTFont(_PDF_FONT_NAME, font_path))
    return _PDF_FONT_NAME


def build_pdf(rows: list[ReportRow], *, filter_note: str, generated_at: Optional[datetime] = None) -> bytes:
    from reportlab.lib import colors  # lazy
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    font = _register_thai_font()
    title_style = ParagraphStyle("title", fontName=font, fontSize=16, leading=20)
    note_style = ParagraphStyle("note", fontName=font, fontSize=11, leading=15)

    buffer = io.BytesIO()
    document = SimpleDocTemplate(
        buffer,
        pagesize=landscape(A4),
        leftMargin=12 * mm,
        rightMargin=12 * mm,
        topMargin=12 * mm,
        bottomMargin=12 * mm,
        title=REPORT_TITLE,
    )

    data = [COLUMN_HEADERS]
    data += [
        [
            row.student_code,
            row.full_name,
            row.faculty,
            str(row.year_level),
            row.category_name,
            _format_hours(row.earned_hours),
            _format_hours(row.required_hours),
            row.status_text,
        ]
        for row in rows
    ]

    table = Table(
        data,
        colWidths=[26 * mm, 55 * mm, 45 * mm, 16 * mm, 60 * mm, 24 * mm, 28 * mm, 20 * mm],
        # หัวตารางซ้ำทุกหน้า — รายงานหลายร้อยแถวกินหลายหน้า ถ้าไม่ซ้ำหน้าหลัง ๆ
        # จะอ่านไม่ออกว่าคอลัมน์ไหนคืออะไร
        repeatRows=1,
    )
    table.setStyle(
        TableStyle(
            [
                ("FONTNAME", (0, 0), (-1, -1), font),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8EAF6")),
                ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#9E9E9E")),
                ("ALIGN", (3, 1), (3, -1), "CENTER"),
                ("ALIGN", (5, 1), (7, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F5F5")]),
            ]
        )
    )

    story = [
        Paragraph(REPORT_TITLE, title_style),
        Spacer(1, 4),
        Paragraph(f"เงื่อนไข: {filter_note}", note_style),
        Paragraph(
            f"ออกรายงานเมื่อ {format_thai_datetime(generated_at or now_th_naive())} "
            f"· ทั้งหมด {len(rows)} รายการ",
            note_style,
        ),
        Spacer(1, 8),
        table,
    ]
    document.build(story)
    return buffer.getvalue()
