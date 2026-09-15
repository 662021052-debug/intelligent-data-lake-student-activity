"""Perceptual hash (pHash) ของไฟล์หลักฐานภาพ — ชั้นที่สองของการกันไฟล์ซ้ำ (OCR เฟส 3A)

checksum (SHA-256) จับได้แค่ไฟล์ที่เหมือนเป๊ะทุกไบต์ ครอป/บีบอัด/แก้พิกเซลเดียวก็เลี่ยงได้
pHash (DCT-based) ของภาพที่ต่างกันแค่การบีบอัด/ปรับขนาดจะออกมาใกล้กัน วัดกันด้วย
Hamming distance (จำนวนบิตที่ต่าง จาก 64 บิต)

* hash size 16 → 256 บิต เก็บเป็น hex 64 ตัวใน ``raw_file.phash``
  (เดิมสเปกให้ 8 → 64 บิต แต่วัดบนเกียรติบัตรจริงแล้วใบเทมเพลตเดียวกันคนละคนชนกันที่ ≤6 บิต
  21/374 คู่ ขณะที่ 256 บิตคู่คนละใบห่างอย่างน้อย 24 บิต และสำเนาบีบอัด/ย่ออยู่ใน ≤16 บิต)
* เฉพาะไฟล์ภาพ — PDF ข้ามไว้ก่อน (เฟส 3B)
* ถอดภาพไม่ได้ (ไฟล์เสีย / ชนิดไฟล์หลอก) → None ไม่ทำให้การอัปโหลดล้ม

``imagehash`` (ดึง numpy/scipy มาด้วย) import แบบ lazy เหมือน easyocr/minio เพื่อไม่ให้
แอปบูตช้าลง
"""
from __future__ import annotations

import io
import logging
from typing import Optional

logger = logging.getLogger("uvicorn.error")

PHASH_SIZE = 16  # ตาราง DCT 16x16 → 256 บิต
PHASH_BITS = PHASH_SIZE * PHASH_SIZE
PHASH_HEX_LENGTH = PHASH_BITS // 4  # 64


def compute_phash(data: bytes, content_type: str) -> Optional[str]:
    """pHash (hex 64 ตัว) ของไฟล์ภาพ หรือ None ถ้าไม่ใช่ภาพ / ถอดภาพไม่ได้"""
    if not content_type.startswith("image/"):
        return None
    try:
        import imagehash
        from PIL import Image, ImageOps

        with Image.open(io.BytesIO(data)) as image:
            # ภาพถ่ายมือถือเก็บทิศทางไว้ใน EXIF — หมุนให้ตั้งตรงก่อน ไม่งั้นรูปเดียวกัน
            # ที่ถูกบันทึกคนละทิศได้ hash ห่างกันจนจับไม่ได้
            upright = ImageOps.exif_transpose(image)
            return str(imagehash.phash(upright, hash_size=PHASH_SIZE))
    except Exception as exc:  # noqa: BLE001 - pHash เป็นตัวช่วย ต้องไม่ทำให้การอัปโหลดล้ม
        logger.info("คำนวณ pHash ไม่ได้ (%s): %s", content_type, exc)
        return None


def phash_distance(a: str, b: str) -> int:
    """Hamming distance ระหว่าง pHash สองค่า (0 = เหมือนกัน · 256 = ต่างทุกบิต)"""
    import imagehash

    # ImageHash.__sub__ คืน numpy.int64 — แปลงเป็น int ธรรมดาให้ใช้ต่อใน JSON/log/เทียบค่าได้ตรง ๆ
    return int(imagehash.hex_to_hash(a) - imagehash.hex_to_hash(b))
