"""ดาวน์โหลดรายงานชั่วโมงกิจกรรมเป็นไฟล์ Excel / PDF (ข้อ 6.5) — staff และ admin

นิสิตดูชั่วโมงตัวเองได้อยู่แล้วผ่าน `/students/me/hours-summary` รายงานรวมทั้ง
มหาวิทยาลัยจึงจำกัดไว้ที่ผู้ปฏิบัติงาน (`require_writer` = staff/admin)
"""

from typing import Literal, Optional
from urllib.parse import quote

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlmodel import Session

from app.auth import require_writer
from app.database import get_session
from app.report_pdf import build_pdf, build_summary_pdf
from app.reports import (
    LARGE_REPORT_ROWS,
    MODE_DETAIL,
    MODE_SUMMARY,
    PDF_MEDIA_TYPE,
    XLSX_MEDIA_TYPE,
    ThaiFontMissingError,
    build_xlsx,
    count_report_rows,
    describe_filters,
    estimate_pdf_pages,
    fetch_report_rows,
    fetch_report_summary,
    report_filename,
)

router = APIRouter(prefix="/reports", tags=["reports"], dependencies=[Depends(require_writer)])


def _attachment_headers(filename: str) -> dict[str, str]:
    """Content-Disposition ที่พาชื่อไฟล์ภาษาไทยไปได้จริง

    ค่าใน header ต้องเป็น latin-1 ชื่อไทยจึงส่งตรง ๆ ไม่ได้ — ใช้ `filename*`
    (RFC 5987, percent-encoded UTF-8) เป็นตัวหลัก และคง `filename` แบบ ASCII ไว้
    ให้เบราว์เซอร์/ตัวแทนเก่าที่ไม่รู้จัก `filename*` ยังได้ชื่อที่ใช้งานได้
    """
    ascii_fallback = "student-hours-report" + filename[filename.rfind(".") :]
    return {
        "Content-Disposition": (
            f"attachment; filename=\"{ascii_fallback}\"; "
            f"filename*=UTF-8''{quote(filename)}"
        )
    }


@router.get("/student-hours/count")
def student_hours_count(
    faculty: Optional[str] = None,
    year_level: Optional[int] = Query(None, ge=1, le=8),
    session: Session = Depends(get_session),
):
    """จำนวนแถวของแต่ละรูปแบบตามตัวกรอง — ให้หน้าเว็บเตือนก่อนออกไฟล์ใหญ่ โดยไม่ต้องสร้างไฟล์"""
    students, detail_rows = count_report_rows(session, faculty=faculty, year_level=year_level)
    return {
        "students": students,
        "summary_rows": students,
        "detail_rows": detail_rows,
        "summary_pages": estimate_pdf_pages(students),
        "detail_pages": estimate_pdf_pages(detail_rows),
        "large_threshold": LARGE_REPORT_ROWS,
    }


@router.get("/student-hours.xlsx")
def student_hours_xlsx(
    faculty: Optional[str] = None,
    year_level: Optional[int] = Query(None, ge=1, le=8),
    semester: Optional[int] = Query(None, ge=1, le=3),
    session: Session = Depends(get_session),
):
    rows = fetch_report_rows(session, faculty=faculty, year_level=year_level, semester=semester)
    content = build_xlsx(rows, filter_note=describe_filters(faculty, year_level, semester))
    return Response(
        content=content,
        media_type=XLSX_MEDIA_TYPE,
        headers=_attachment_headers(report_filename("xlsx")),
    )


@router.get("/student-hours.pdf")
def student_hours_pdf(
    faculty: Optional[str] = None,
    year_level: Optional[int] = Query(None, ge=1, le=8),
    semester: Optional[int] = Query(None, ge=1, le=3),
    mode: Literal["summary", "detail"] = Query(MODE_SUMMARY, description="summary = 1 แถวต่อนิสิต · detail = 1 แถวต่อหมวด"),
    session: Session = Depends(get_session),
):
    note = describe_filters(faculty, year_level, semester)
    try:
        if mode == MODE_DETAIL:
            rows = fetch_report_rows(session, faculty=faculty, year_level=year_level, semester=semester)
            content = build_pdf(rows, filter_note=note)
        else:
            summaries = fetch_report_summary(session, faculty=faculty, year_level=year_level, semester=semester)
            content = build_summary_pdf(summaries, filter_note=note)
    except ThaiFontMissingError as exc:
        # 503: ปัญหาของเซิร์ฟเวอร์ (ไม่มีฟอนต์) ไม่ใช่คำขอที่ผิด — ผู้ใช้แก้เองไม่ได้
        # แต่ยังดาวน์โหลด Excel ได้ตามปกติ
        raise HTTPException(status_code=503, detail=str(exc))
    return Response(
        content=content,
        media_type=PDF_MEDIA_TYPE,
        headers=_attachment_headers(report_filename("pdf")),
    )
