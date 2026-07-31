"""สร้างรูป "ใบประกาศ/หลักฐานการเข้าร่วม" สำหรับข้อมูลตัวอย่าง (seed).

เดิม seed ใช้ PNG ขนาด 1x1 ก้อนเดียวซ้ำทุก participation ทำให้
* OCR ไม่มีข้อความให้อ่านเลย (ยิ่งกว่านั้นไฟล์นั้น decode ไม่ผ่านด้วยซ้ำ) ทุกแถวจึงจบที่
  ``needs_review`` และไม่มีทางเกิดเคส ``auto_approved`` ให้เห็น
* ทุกไฟล์มี checksum เดียวกัน ตัวตรวจไฟล์ซ้ำจึงติดธง ``flagged`` ใส่ข้อมูลปกติ

โมดูลนี้วาดใบประกาศจริงด้วย Pillow: ชื่อนิสิต + ชื่อกิจกรรม + วันที่ + หมวดชั่วโมง
พร้อมเลขอ้างอิงที่ไม่ซ้ำกัน ทำให้ทุกไฟล์มี checksum ต่างกัน

แยกออกมาจาก ``seed.py`` เพื่อให้ import ไปเขียน test ได้
"""
from __future__ import annotations

import io
import random
from datetime import datetime
from pathlib import Path
from typing import Optional

THAI_MONTHS = [
    "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
    "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม",
]

# ฟอนต์ไทยที่ยอมรับได้ เรียงตามลำดับความชอบ
# tlwg = แพ็กเกจ fonts-thai-tlwg ที่ Dockerfile ติดตั้ง, ที่เหลือเผื่อรันบนเครื่อง dev
_FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/tlwg/Sarabun.ttf",
    "/usr/share/fonts/truetype/tlwg/Loma.ttf",
    "/usr/share/fonts/truetype/tlwg/Garuda.ttf",
    "/usr/share/fonts/truetype/tlwg/Waree.ttf",
    "/usr/share/fonts/truetype/noto/NotoSansThai-Regular.ttf",
    "C:/Windows/Fonts/leelawui.ttf",
    "C:/Windows/Fonts/leelawad.ttf",
    "C:/Windows/Fonts/tahoma.ttf",
    "/System/Library/Fonts/Supplemental/Ayuthaya.ttf",
]

# สัดส่วนของหลักฐานแต่ละแบบ ให้ผลการตรวจออกมาปนกันเหมือนของจริง
# (ใบสมบูรณ์ควรผ่านอัตโนมัติ ที่เหลือควรตกมาให้เจ้าหน้าที่ตรวจ)
VARIANT_FULL = "full"
VARIANT_NO_NAME = "no_name"
VARIANT_LOW_QUALITY = "low_quality"


def find_thai_font() -> Optional[str]:
    """path ของฟอนต์ไทยตัวแรกที่เจอในเครื่อง (None ถ้าไม่มีเลย)"""
    for path in _FONT_CANDIDATES:
        if Path(path).exists():
            return path
    return None


def thai_date(dt: datetime) -> str:
    """'14 ตุลาคม 2568' — วันที่แบบไทย ปีพุทธศักราช"""
    return f"{dt.day} {THAI_MONTHS[dt.month - 1]} {dt.year + 543}"


def pick_variant(rng: random.Random) -> str:
    """สุ่มชนิดหลักฐาน: ส่วนใหญ่เป็นใบประกาศสมบูรณ์ ที่เหลือเป็นเคสที่ต้องให้คนตรวจ"""
    roll = rng.random()
    if roll < 0.75:
        return VARIANT_FULL
    if roll < 0.90:
        return VARIANT_NO_NAME
    return VARIANT_LOW_QUALITY


def render_certificate(
    *,
    student_name: str,
    activity_name: str,
    activity_date: datetime,
    category_path: str,
    reference: str,
    variant: str = VARIANT_FULL,
    font_path: Optional[str] = None,
) -> bytes:
    """วาดใบประกาศเป็น PNG แล้วคืนเป็น bytes

    [reference] คือเลขอ้างอิงที่ไม่ซ้ำกัน — เป็นตัวรับประกันว่า checksum ของทุกไฟล์ต่างกัน
    [variant] คุมคุณภาพ/ความครบของข้อมูลบนใบ เพื่อให้ผลการตรวจปนกันสมจริง
    """
    from PIL import Image, ImageDraw, ImageFilter, ImageFont

    width, height = 1000, 700
    image = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(image)

    def font(size: int):
        if font_path:
            return ImageFont.truetype(font_path, size)
        return ImageFont.load_default()

    def centered(text: str, y: int, size: int, fill: str = "black") -> None:
        f = font(size)
        text_width = draw.textbbox((0, 0), text, font=f)[2]
        draw.text(((width - text_width) / 2, y), text, font=f, fill=fill)

    # กรอบใบประกาศ
    draw.rectangle([(24, 24), (width - 24, height - 24)], outline="#1f3d7a", width=6)
    draw.rectangle([(40, 40), (width - 40, height - 40)], outline="#c9a227", width=2)

    centered("มหาวิทยาลัยทักษิณ", 80, 34, "#1f3d7a")
    centered("เกียรติบัตรฉบับนี้ให้ไว้เพื่อแสดงว่า", 150, 28)

    if variant == VARIANT_NO_NAME:
        # ภาพป้ายงาน/ภาพหมู่ที่ไม่มีชื่อผู้เข้าร่วม — ตรวจอัตโนมัติไม่ได้ ต้องให้คนดู
        centered("ผู้เข้าร่วมกิจกรรม", 215, 40, "#1f3d7a")
    else:
        centered(student_name, 210, 44, "#1f3d7a")

    centered("ได้เข้าร่วมกิจกรรม", 290, 28)
    centered(activity_name, 340, 38, "#1f3d7a")
    centered(f"หมวด {category_path}", 410, 24, "#444444")
    centered(f"จัดขึ้นเมื่อวันที่ {thai_date(activity_date)}", 460, 26)
    centered("ให้ไว้ ณ วันที่ " + thai_date(activity_date), 510, 22, "#444444")
    centered(f"เลขที่อ้างอิง {reference}", 600, 20, "#666666")

    if variant == VARIANT_LOW_QUALITY:
        # จำลองภาพถ่ายจากมือถือที่เบลอ/ความละเอียดต่ำ — OCR อ่านได้ไม่มั่นใจ
        image = image.resize((width // 3, height // 3)).resize((width, height))
        image = image.filter(ImageFilter.GaussianBlur(radius=2.2))

    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()
