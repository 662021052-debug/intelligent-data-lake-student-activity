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


# Sarabun (Google Fonts, SIL OFL) ที่แนบมากับโค้ด — ฟอนต์ตัวเดียวกับที่หน้าเว็บใช้
# รายงาน PDF ใช้ตัวนี้เป็นหลักเพื่อให้หน้าตาเหมือนกันทุกเครื่อง (เครื่อง dev, Docker, เซิร์ฟเวอร์)
# แทนที่จะขึ้นกับว่า OS นั้นติดตั้งฟอนต์อะไรไว้ · ไม่ได้แตะ FONT_CANDIDATES เพราะ seed ใบประกาศ
# ใช้รายการนั้นและ OCR ผูกกับหน้าตาฟอนต์เดิม
REPORT_FONT_DIR = Path(__file__).parent / "assets" / "fonts"


def find_report_fonts() -> tuple[Optional[str], Optional[str]]:
    """(ฟอนต์ปกติ, ฟอนต์ตัวหนา) สำหรับรายงาน PDF — ตัวหนาเป็น None ถ้าไม่มี (หัวตารางใช้ตัวปกติแทน)

    ตัวปกติเป็น None ก็ต่อเมื่อไม่มีทั้ง Sarabun ที่แนบมาและฟอนต์ไทยใด ๆ ในเครื่อง
    """
    regular = REPORT_FONT_DIR / "Sarabun-Regular.ttf"
    bold = REPORT_FONT_DIR / "Sarabun-Bold.ttf"
    if regular.exists():
        return str(regular), (str(bold) if bold.exists() else None)
    return find_thai_font(), None


def find_thai_font() -> Optional[str]:
    """path ของฟอนต์ไทยตัวแรกที่เจอในเครื่อง (None ถ้าไม่มีเลย)"""
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    return None
