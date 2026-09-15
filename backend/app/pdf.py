"""render หน้า PDF เป็นภาพ PNG ด้วย PyMuPDF (OCR เฟส 3B)

EasyOCR อ่านได้แต่ภาพ เดิม PDF จึงไม่ถูก OCR เลย (เด้ง needs_review เสมอ) โมดูลนี้แปลงหน้า PDF
เป็นภาพให้ส่งเข้า OCR ได้เหมือนไฟล์ภาพ และให้ pHash ใช้หน้าแรกได้

* จำกัดจำนวนหน้า — OCR บน CPU ใช้หน้าละหลายวินาที
* จำกัดด้านยาวสุดของภาพ — หน้า PDF ขนาดผิดปกติจะไม่กลายเป็นภาพหลายหมื่นพิกเซล
* ไฟล์เสีย / ติดรหัสผ่าน / ไม่ใช่ PDF → โยน exception ให้ผู้เรียกตัดสินเอง
  (silver คืน ("", 0) · pHash คืน None) ไม่กลืนไว้ที่นี่

``pymupdf`` import แบบ lazy เหมือน easyocr/imagehash
"""
from __future__ import annotations

POINTS_PER_INCH = 72  # หน่วยของหน้า PDF


def render_pdf_pages(data: bytes, *, max_pages: int, dpi: int, max_side_px: int) -> list[bytes]:
    """ภาพ PNG ของ [max_pages] หน้าแรก ที่ความละเอียด [dpi] (ด้านยาวไม่เกิน [max_side_px])"""
    import pymupdf

    pages: list[bytes] = []
    with pymupdf.open(stream=data, filetype="pdf") as doc:
        for index in range(min(max_pages, doc.page_count)):
            page = doc.load_page(index)
            zoom = dpi / POINTS_PER_INCH
            longest_pt = max(page.rect.width, page.rect.height)
            if longest_pt * zoom > max_side_px:
                zoom = max_side_px / longest_pt
            pixmap = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
            pages.append(pixmap.tobytes("png"))
    return pages


def extract_text_layer(data: bytes, *, max_pages: int) -> str:
    """ข้อความที่ฝังอยู่ใน PDF (text layer) ของ [max_pages] หน้าแรก — "" ถ้าเป็น PDF ภาพล้วน

    PDF ที่ export จากโปรแกรม (Word / Canva / ระบบออกเกียรติบัตร) มีข้อความจริงอยู่แล้ว อ่านตรง ๆ
    ได้ถูกทุกตัวรวมวรรณยุกต์ ส่วน PDF ที่สแกนมาเป็นภาพจะไม่มี (ต้อง render + OCR)
    หน้าที่ไม่มีข้อความข้ามไป · ขึ้นบรรทัดใหม่คั่นระหว่างหน้า
    """
    import pymupdf

    texts: list[str] = []
    with pymupdf.open(stream=data, filetype="pdf") as doc:
        for index in range(min(max_pages, doc.page_count)):
            text = doc.load_page(index).get_text().strip()
            if text:
                texts.append(text)
    return "\n".join(texts)
