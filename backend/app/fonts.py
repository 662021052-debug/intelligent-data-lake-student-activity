"""หาไฟล์ฟอนต์ไทยในเครื่อง — ใช้ร่วมกันระหว่าง seed (วาดใบประกาศ) กับรายงาน PDF

ทั้งสองงานพังแบบเดียวกันเมื่อไม่มีฟอนต์ไทย (ตัวอักษรกลายเป็นกล่องสี่เหลี่ยม) จึงควร
มีรายชื่อฟอนต์ชุดเดียว ไม่ใช่คนละชุดที่ค่อย ๆ เพี้ยนออกจากกัน
"""

from pathlib import Path
from typing import Optional

# ฟอนต์ไทยที่ยอมรับได้ เรียงตามลำดับความชอบ
# tlwg = แพ็กเกจ fonts-thai-tlwg ที่ Dockerfile ติดตั้ง, ที่เหลือเผื่อรันบนเครื่อง dev
FONT_CANDIDATES = [
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


def find_thai_font() -> Optional[str]:
    """path ของฟอนต์ไทยตัวแรกที่เจอในเครื่อง (None ถ้าไม่มีเลย)"""
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    return None
