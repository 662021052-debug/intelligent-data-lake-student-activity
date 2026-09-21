"""ตัวช่วยจัดข้อความไทยสำหรับ reportlab (รายงาน PDF)

reportlab วาดทีละตัวอักษรตามที่ฟอนต์บอก ไม่มี text shaping (ไม่อ่าน GPOS/GSUB ของฟอนต์) ทำให้เกิด
ปัญหา 2 อย่างกับภาษาไทยที่ต้องแก้เอง:

1. **วรรณยุกต์ทับสระบน/หลุดหาย** — `ที่ นี้ ซึ่ง ชั่ว` วรรณยุกต์ถูกวาดซ้อนตำแหน่งเดียวกับสระบน
   (`ชั่ว` กลายเป็น `ชัว`) และ `ป่า ปู่ ฝ่าย` วรรณยุกต์จมอยู่ในหัวตัวอักษร ป ฝ ฟ ฬ จนมองไม่เห็น
   → ยกวรรณยุกต์ขึ้นตามที่ shaping ปกติจะทำ (`stacked_marks_markup`)
2. **ตัดบรรทัดไม่เป็น** — reportlab ตัดบรรทัดเฉพาะที่ช่องว่าง ชื่อคณะที่ไม่มีช่องว่างเลย
   (`คณะวิทยาศาสตร์และนวัตกรรมดิจิทัล`) จึงล้นออกนอกเซลล์ไปชนคอลัมน์ข้าง ๆ
   → ตัดเองที่ช่องว่าง/คำเชื่อมก่อน และที่ขอบพยางค์ตัวอักษรเป็นทางเลือกสุดท้าย (`wrap_text`)
"""

from __future__ import annotations

import re
import unicodedata
from typing import Callable
from xml.sax.saxutils import escape

# --------------------------- วรรณยุกต์ซ้อน ---------------------------
_UPPER_VOWELS = "ัิีึื็ํ"  # ั ิ ี ึ ื ็ ํ
_TONE_MARKS = "่้๊๋์"  # ่ ้ ๊ ๋ ์
_LOWER_VOWELS = "ฺุู"  # ุ ู ฺ
_ASCENDERS = "ปฝฟฬ"  # พยัญชนะหัวสูง — วรรณยุกต์ที่ตามมาจมเข้าไปในหัว

_STACKED = re.compile(f"([{_UPPER_VOWELS}]|[{_ASCENDERS}][{_LOWER_VOWELS}]?)([{_TONE_MARKS}])")

# ระยะที่ยกวรรณยุกต์ขึ้น เป็นสัดส่วนของขนาดฟอนต์ — ค่าที่ลองบนฟอนต์ Sarabun แล้ววรรณยุกต์
# พ้นสระบน/หัว ป ฝ ฟ โดยไม่ลอยห่างจนดูเหมือนอยู่ผิดตัว
MARK_RISE_EM = 0.2


def stacked_marks_markup(text: str, size: float) -> str:
    """escape ข้อความเป็น markup ของ Paragraph และยกวรรณยุกต์ที่ซ้อนสระบน/หัว ป ฝ ฟ ฬ ขึ้น"""
    rise = round(size * MARK_RISE_EM, 2)
    return _STACKED.sub(
        lambda m: f'{m.group(1)}<super rise="{rise}" size="{size:g}">{m.group(2)}</super>',
        escape(text),
    )


def has_stacked_marks(text: str) -> bool:
    return _STACKED.search(text) is not None


# --------------------------- ตัดบรรทัด ---------------------------
_LEADING_VOWELS = "เแโใไ"  # อยู่หน้าพยัญชนะ ห้ามค้างท้ายบรรทัด
_NO_LINE_START = set("ะาำๆฯ")  # ห้ามขึ้นต้นบรรทัด (ตัวที่ไม่ใช่ตัวผสมแต่ต้องต่อกับตัวหน้า)
# คำเชื่อมที่เป็นรอยต่อธรรมชาติของชื่อคณะ/หน่วยงาน — ตัดหน้าคำเหล่านี้ก่อนจะตัดกลางคำ
_SOFT_BREAK_BEFORE = re.compile("(?=และ|เพื่อ|หรือ|แห่ง|ของ)")


def _clusters(word: str) -> list[str]:
    """แบ่งเป็นกลุ่มตัวอักษรที่ห้ามแยก (สระหน้า+พยัญชนะ+สระ/วรรณยุกต์ที่ตามมา)"""
    result: list[str] = []
    for ch in word:
        glued = (
            not result
            or unicodedata.category(ch) == "Mn"
            or ch in _NO_LINE_START
            or result[-1][-1] in _LEADING_VOWELS
        )
        if glued and result:
            result[-1] += ch
        else:
            result.append(ch)
    return result


def _split_long(chunk: str, max_width: float, measure: Callable[[str], float]) -> list[str]:
    """แบ่งชิ้นที่ยาวเกินความกว้างตามขอบกลุ่มตัวอักษร (ทางเลือกสุดท้าย)"""
    lines: list[str] = []
    current = ""
    for cluster in _clusters(chunk):
        if current and measure(current + cluster) > max_width:
            lines.append(current)
            current = cluster
        else:
            current += cluster
    if current:
        lines.append(current)
    return lines


def wrap_text(text: str, max_width: float, measure: Callable[[str], float]) -> list[str]:
    """ตัด [text] เป็นบรรทัดที่กว้างไม่เกิน [max_width] (หน่วยเดียวกับ [measure])

    ตัดที่ช่องว่างก่อน แล้วที่คำเชื่อม (และ/เพื่อ/หรือ/แห่ง/ของ) แล้วค่อยที่ขอบกลุ่มตัวอักษร
    ไม่ตัดให้สระ/วรรณยุกต์ขึ้นต้นบรรทัด และไม่ปล่อยสระหน้า (เ แ โ ใ ไ) ค้างท้ายบรรทัด
    ข้อความที่พอดีอยู่แล้วคืนกลับเป็นบรรทัดเดียวไม่แตะต้อง
    """
    text = " ".join(text.split())
    if not text:
        return [""]
    if measure(text) <= max_width:
        return [text]

    # ชิ้นที่ห้ามแยกถ้าไม่จำเป็น — (ข้อความ, ต้องมีช่องว่างนำหน้าไหมถ้าไม่ใช่ต้นบรรทัด)
    chunks: list[tuple[str, bool]] = []
    for word_index, word in enumerate(text.split(" ")):
        for part_index, part in enumerate(p for p in _SOFT_BREAK_BEFORE.split(word) if p):
            chunks.append((part, word_index > 0 and part_index == 0))

    lines: list[str] = []
    current = ""
    for chunk, space_before in chunks:
        joined = current + (" " if current and space_before else "") + chunk
        if not current or measure(joined) <= max_width:
            current = joined
            if measure(current) > max_width:  # ชิ้นเดียวยาวเกิน (current ว่างมาก่อน)
                pieces = _split_long(current, max_width, measure)
                lines.extend(pieces[:-1])
                current = pieces[-1]
            continue
        lines.append(current)
        current = chunk
        if measure(current) > max_width:
            pieces = _split_long(current, max_width, measure)
            lines.extend(pieces[:-1])
            current = pieces[-1]
    if current:
        lines.append(current)
    return lines
