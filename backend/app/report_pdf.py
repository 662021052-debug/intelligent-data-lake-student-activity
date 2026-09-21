"""สร้าง PDF ของรายงานชั่วโมงกิจกรรม (reportlab) — ข้อ 6.5

แยกจาก ``reports.py`` (ข้อมูล + Excel) เพราะการจัดหน้า PDF ภาษาไทยมีรายละเอียดเยอะ:

* ความกว้างคอลัมน์คำนวณจากเนื้อหาจริง (ชื่อคณะที่ยาวที่สุดต้องอยู่ในเซลล์ได้) ถ้าเกินหน้า
  จึงบีบคอลัมน์ข้อความที่กว้างสุดแล้วตัดบรรทัดในเซลล์ — ห้ามล้นไปชนคอลัมน์ข้าง ๆ
* ทุกเซลล์มี padding ซ้าย-ขวา · ชั้นปี/ตัวเลข/สถานะจัดกึ่งกลาง
* ฟอนต์ Sarabun ฝังในไฟล์ · วรรณยุกต์ที่ซ้อนสระบนถูกยกขึ้น (ดู ``thai_text``)
* หัวตารางซ้ำทุกหน้า + เลข "หน้า x/y" ท้ายทุกหน้า

``reportlab`` import แบบ lazy เหมือนที่เหลือของระบบรายงาน
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from datetime import datetime
from functools import lru_cache
from typing import Callable, Optional, Sequence

from app.fonts import find_report_fonts
from app.reports import (
    COLUMN_HEADERS,
    REPORT_TITLE,
    SUMMARY_COLUMN_HEADERS,
    ReportRow,
    StudentSummary,
    ThaiFontMissingError,
    _format_hours,
)
from app.thai_text import has_stacked_marks, stacked_marks_markup, wrap_text
from app.timeutil import format_thai_datetime, now_th_naive

_PDF_FONT_NAME = "ThaiReport"
_PDF_BOLD_FONT_NAME = "ThaiReportBold"

_FONT_SIZE = 9
_NOTE_SIZE = 10.5
_LEADING = 12.5
_PAD_X_MM = 2.5  # ช่องว่างซ้าย-ขวาในทุกเซลล์ — ตัวอักษรห้ามติดเส้นขอบ
_PAD_Y = 3.5
_MIN_FLEX_MM = 24  # คอลัมน์ข้อความแคบสุดที่ยอมให้บีบก่อนต้องตัดบรรทัด
_PT_PER_MM = 72 / 25.4
# เผื่อความกว้างให้ทุกคอลัมน์ — Paragraph ตัดบรรทัดกลางคำถ้าข้อความกว้างเท่าพื้นที่เป๊ะ ๆ
# (ค่าทศนิยมคลาดกันนิดเดียวก็ล้น) ซึ่งเคยทำให้หัว "ชั่วโมงที่ต้องการ" ขาดเป็น "...การ" / "ร"
_FIT_SLACK = 4.0


def _register_thai_font() -> tuple[str, str]:
    """ลงทะเบียนฟอนต์ไทยกับ reportlab แล้วคืน (ชื่อตัวปกติ, ชื่อตัวหนา สำหรับหัวตาราง)"""
    from reportlab.pdfbase import pdfmetrics  # lazy
    from reportlab.pdfbase.ttfonts import TTFont

    registered = pdfmetrics.getRegisteredFontNames()
    if _PDF_FONT_NAME in registered:
        return _PDF_FONT_NAME, (_PDF_BOLD_FONT_NAME if _PDF_BOLD_FONT_NAME in registered else _PDF_FONT_NAME)

    regular, bold = find_report_fonts()
    if regular is None:
        raise ThaiFontMissingError(
            "ไม่พบฟอนต์ภาษาไทยในเครื่องนี้ จึงสร้างไฟล์ PDF ไม่ได้ "
            "(ติดตั้งแพ็กเกจ fonts-thai-tlwg แล้วลองใหม่ หรือใช้ Excel แทน)"
        )
    pdfmetrics.registerFont(TTFont(_PDF_FONT_NAME, regular))
    if bold:
        pdfmetrics.registerFont(TTFont(_PDF_BOLD_FONT_NAME, bold))
        return _PDF_FONT_NAME, _PDF_BOLD_FONT_NAME
    return _PDF_FONT_NAME, _PDF_FONT_NAME


@dataclass(frozen=True)
class PdfColumn:
    header: str
    values: Sequence[str]
    align: str  # LEFT / CENTER
    flex: bool = False  # คอลัมน์ข้อความ: ปรับความกว้างตามเนื้อหา + ตัดบรรทัดในเซลล์ได้


def detail_columns(rows: Sequence[ReportRow]) -> list[PdfColumn]:
    return [
        PdfColumn(COLUMN_HEADERS[0], [r.student_code for r in rows], "LEFT"),
        PdfColumn(COLUMN_HEADERS[1], [r.full_name for r in rows], "LEFT", flex=True),
        PdfColumn(COLUMN_HEADERS[2], [r.faculty for r in rows], "LEFT", flex=True),
        PdfColumn(COLUMN_HEADERS[3], [str(r.year_level) for r in rows], "CENTER"),
        PdfColumn(COLUMN_HEADERS[4], [r.category_name for r in rows], "LEFT", flex=True),
        PdfColumn(COLUMN_HEADERS[5], [_format_hours(r.earned_hours) for r in rows], "CENTER"),
        PdfColumn(COLUMN_HEADERS[6], [_format_hours(r.required_hours) for r in rows], "CENTER"),
        PdfColumn(COLUMN_HEADERS[7], [r.status_text for r in rows], "CENTER"),
    ]


def summary_columns(rows: Sequence[StudentSummary]) -> list[PdfColumn]:
    return [
        PdfColumn(SUMMARY_COLUMN_HEADERS[0], [r.student_code for r in rows], "LEFT"),
        PdfColumn(SUMMARY_COLUMN_HEADERS[1], [r.full_name for r in rows], "LEFT", flex=True),
        PdfColumn(SUMMARY_COLUMN_HEADERS[2], [r.faculty for r in rows], "LEFT", flex=True),
        PdfColumn(SUMMARY_COLUMN_HEADERS[3], [str(r.year_level) for r in rows], "CENTER"),
        PdfColumn(SUMMARY_COLUMN_HEADERS[4], [_format_hours(r.total_hours) for r in rows], "CENTER"),
        PdfColumn(SUMMARY_COLUMN_HEADERS[5], [r.items_text for r in rows], "CENTER"),
        PdfColumn(SUMMARY_COLUMN_HEADERS[6], [r.status_text for r in rows], "CENTER"),
    ]


def column_widths(
    columns: Sequence[PdfColumn],
    available: float,
    measure: Callable[[str], float],
    pad_x: float,
    min_flex: float = _MIN_FLEX_MM * _PT_PER_MM,
) -> list[float]:
    """ความกว้างคอลัมน์ (pt) ที่พอดีกับเนื้อหาจริง รวมกันไม่เกิน [available]

    ทุกคอลัมน์เริ่มที่ความกว้างของข้อความที่ยาวสุด (รวมหัวคอลัมน์) + padding — ชื่อคณะที่ยาว
    ที่สุดจึงอยู่บรรทัดเดียวได้ถ้าที่พอ · ถ้ารวมกันเกินหน้า จะบีบเฉพาะคอลัมน์ข้อความ โดยลดตัวที่
    กว้างสุดลงมาเท่าตัวรองลงมาก่อน (ไม่บีบตัวที่แคบอยู่แล้ว) ตัวที่ล้นจะถูกตัดบรรทัดในเซลล์ ·
    ถ้าเหลือที่ แบ่งให้คอลัมน์ข้อความเท่า ๆ กัน ตารางจะได้เต็มความกว้างหน้า ไม่แคบชิดซ้าย
    """
    widths = [
        max([measure(column.header)] + [measure(v) for v in set(column.values)]) + 2 * pad_x + _FIT_SLACK
        for column in columns
    ]
    flex = [i for i, c in enumerate(columns) if c.flex]

    overflow = sum(widths) - available
    while overflow > 0.01:
        shrinkable = [i for i in flex if widths[i] > min_flex + 0.01]
        if not shrinkable:
            break  # เกินหน้าทั้งที่บีบสุดแล้ว — ปล่อยให้ตารางล้นขวาน้อยกว่าล้นเซลล์ (ไม่เกิดกับข้อมูลจริง)
        widest = max(widths[i] for i in shrinkable)
        tier = [i for i in shrinkable if widths[i] >= widest - 0.01]
        below = [widths[i] for i in shrinkable if i not in tier]
        floor = max(max(below, default=min_flex), min_flex)
        per_column = min(widest - floor, overflow / len(tier))
        for i in tier:
            widths[i] -= per_column
        overflow -= per_column * len(tier)

    slack = available - sum(widths)
    if slack > 0 and flex:
        for i in flex:
            widths[i] += slack / len(flex)
    return widths


def _numbered_canvas_class(font: str):
    """canvas ที่พิมพ์ "หน้า x/y" ท้ายทุกหน้า — ต้องรู้จำนวนหน้ารวมก่อน จึงเก็บสถานะแต่ละหน้าไว้
    แล้ววาดเลขหน้าตอนบันทึกไฟล์"""
    from reportlab.lib.units import mm
    from reportlab.pdfgen import canvas

    class NumberedCanvas(canvas.Canvas):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self._saved_pages: list[dict] = []

        def showPage(self):
            self._saved_pages.append(dict(self.__dict__))
            self._startPage()

        def save(self):
            total = len(self._saved_pages)
            for state in self._saved_pages:
                self.__dict__.update(state)
                self.setFont(font, 8)
                self.setFillGray(0.35)
                self.drawCentredString(self._pagesize[0] / 2, 6 * mm, f"หน้า {self._pageNumber}/{total}")
                super().showPage()
            super().save()

    return NumberedCanvas


def render_pdf(
    columns: Sequence[PdfColumn],
    *,
    row_count: int,
    count_note: str,
    filter_note: str,
    mode_note: str,
    generated_at: Optional[datetime],
) -> bytes:
    from reportlab.lib import colors  # lazy
    from reportlab.lib.enums import TA_CENTER, TA_LEFT
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.pdfbase.pdfmetrics import stringWidth
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    font, bold_font = _register_thai_font()
    title_style = ParagraphStyle("title", fontName=bold_font, fontSize=16, leading=22)
    note_style = ParagraphStyle("note", fontName=font, fontSize=_NOTE_SIZE, leading=15)

    margin = 12 * mm
    available = landscape(A4)[0] - 2 * margin
    pad_x = _PAD_X_MM * mm

    @lru_cache(maxsize=None)
    def measure(value: str) -> float:
        return stringWidth(value, font, _FONT_SIZE)

    @lru_cache(maxsize=None)
    def measure_bold(value: str) -> float:
        return stringWidth(value, bold_font, _FONT_SIZE)

    # หัวคอลัมน์เป็นตัวหนาซึ่งกว้างกว่าตัวปกติ — วัดด้วยตัวที่กว้างกว่าเพื่อไม่ให้หัวล้นเซลล์
    widths = column_widths(columns, available, lambda v: max(measure(v), measure_bold(v)), pad_x)

    alignment = {"LEFT": TA_LEFT, "CENTER": TA_CENTER}
    cell_styles = {
        name: ParagraphStyle(f"cell-{name}", fontName=font, fontSize=_FONT_SIZE, leading=_LEADING, alignment=code)
        for name, code in alignment.items()
    }
    head_styles = {
        name: ParagraphStyle(f"head-{name}", fontName=bold_font, fontSize=_FONT_SIZE, leading=_LEADING, alignment=code)
        for name, code in alignment.items()
    }

    def make_cell(value: str, index: int, header: bool = False):
        inner = widths[index] - 2 * pad_x
        lines = wrap_text(value, inner, measure_bold if header else measure)
        # ข้อความที่พอดีบรรทัดเดียวและไม่มีวรรณยุกต์ซ้อน → ปล่อยเป็น str (เร็วกว่า Paragraph มาก
        # ซึ่งสำคัญตอนออกแบบละเอียดหลายหมื่นแถว) นอกนั้นใช้ Paragraph เพื่อยกวรรณยุกต์/ตัดบรรทัด
        if not header and len(lines) == 1 and not has_stacked_marks(lines[0]):
            return lines[0]
        style = (head_styles if header else cell_styles)[columns[index].align]
        return Paragraph("<br/>".join(stacked_marks_markup(line, _FONT_SIZE) for line in lines), style)

    # ค่าซ้ำ (คณะ/หมวด/สถานะ/ชั้นปี) แปลงเป็นเซลล์ครั้งเดียวต่อคอลัมน์ — วาดซ้ำได้เพราะ
    # ความกว้างของคอลัมน์เท่ากันทุกแถว
    caches: list[dict[str, object]] = [{} for _ in columns]

    def cell(value: str, index: int):
        cache = caches[index]
        if value not in cache:
            cache[value] = make_cell(value, index)
        return cache[value]

    data = [[make_cell(c.header, i, header=True) for i, c in enumerate(columns)]]
    for row_index in range(row_count):
        data.append([cell(c.values[row_index], i) for i, c in enumerate(columns)])

    table = Table(data, colWidths=widths, repeatRows=1)  # หัวตารางซ้ำทุกหน้า
    style = [
        ("FONTNAME", (0, 0), (-1, -1), font),
        ("FONTSIZE", (0, 0), (-1, -1), _FONT_SIZE),
        ("LEADING", (0, 0), (-1, -1), _LEADING),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8EAF6")),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#9E9E9E")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), pad_x),
        ("RIGHTPADDING", (0, 0), (-1, -1), pad_x),
        ("TOPPADDING", (0, 0), (-1, -1), _PAD_Y),
        ("BOTTOMPADDING", (0, 0), (-1, -1), _PAD_Y),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F5F5")]),
    ]
    # ALIGN ใช้กับเซลล์ที่เป็น str · เซลล์ Paragraph ใช้ alignment ของ style ที่ตั้งไว้ข้างบน
    style += [("ALIGN", (i, 0), (i, -1), c.align) for i, c in enumerate(columns)]
    table.setStyle(TableStyle(style))

    buffer = io.BytesIO()
    document = SimpleDocTemplate(
        buffer,
        pagesize=landscape(A4),
        leftMargin=margin,
        rightMargin=margin,
        topMargin=margin,
        bottomMargin=margin + 4 * mm,  # เผื่อที่ให้เลขหน้า
        title=REPORT_TITLE,
    )
    generated = format_thai_datetime(generated_at or now_th_naive())
    story = [
        Paragraph(stacked_marks_markup(REPORT_TITLE, 16), title_style),
        Spacer(1, 4),
        Paragraph(stacked_marks_markup(f"เงื่อนไข: {filter_note}", _NOTE_SIZE), note_style),
        Paragraph(stacked_marks_markup(f"รูปแบบ: {mode_note}", _NOTE_SIZE), note_style),
        Paragraph(stacked_marks_markup(f"ออกรายงานเมื่อ {generated} · {count_note}", _NOTE_SIZE), note_style),
        Spacer(1, 8),
        table,
    ]
    document.build(story, canvasmaker=_numbered_canvas_class(font))
    return buffer.getvalue()


def build_pdf(
    rows: Sequence[ReportRow], *, filter_note: str, generated_at: Optional[datetime] = None
) -> bytes:
    """PDF แบบ **ละเอียด** — หนึ่งแถวต่อหนึ่งหมวดกิจกรรม"""
    students = len({r.student_code for r in rows})
    return render_pdf(
        detail_columns(rows),
        row_count=len(rows),
        count_note=f"ทั้งหมด {len(rows)} รายการ (นิสิต {students} คน)",
        filter_note=filter_note,
        mode_note="แบบละเอียด (1 แถวต่อ 1 หมวดกิจกรรม)",
        generated_at=generated_at,
    )


def build_summary_pdf(
    summaries: Sequence[StudentSummary], *, filter_note: str, generated_at: Optional[datetime] = None
) -> bytes:
    """PDF แบบ **สรุปต่อคน** — หนึ่งแถวต่อนิสิตหนึ่งคน"""
    return render_pdf(
        summary_columns(summaries),
        row_count=len(summaries),
        count_note=f"นิสิตทั้งหมด {len(summaries)} คน",
        filter_note=filter_note,
        mode_note="สรุปต่อนิสิต (ชั่วโมงรวม · จำนวนหมวดที่ครบ · สถานะรวม)",
        generated_at=generated_at,
    )
