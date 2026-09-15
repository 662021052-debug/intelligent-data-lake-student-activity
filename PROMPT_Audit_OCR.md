# Prompt สำหรับ Claude Code — AUDIT ระบบ OCR ตรวจหลักฐาน (อ่านอย่างเดียว)

**อ่านอย่างเดียว — ห้ามแก้/ลบโค้ดหรือข้อมูล · ไม่ต้อง build/test · แค่รายงานกลับ**

เป้าหมายที่จะปรับหลัง audit: (1) อ่านแม่นขึ้น auto-approve ได้มากขึ้น (2) กันเกียรติบัตรปลอม/ส่งซ้ำ
ต้องรู้ก่อนว่าปัจจุบันทำอะไรอยู่ ให้ไล่และรายงานตามหัวข้อ

## 1. Pipeline ปัจจุบัน (ไล่ตั้งแต่รับไฟล์ → ตัดสิน)
- ไฟล์/ฟังก์ชันที่ทำ OCR (คาดว่า silver_evidence_ocr / approval.py / ที่เกี่ยวกับ easyocr) อยู่ตรงไหนบ้าง วาด flow สั้น ๆ
- รับไฟล์ประเภทไหนบ้าง (jpg/png/pdf) · เก็บที่ไหน (MinIO/Bronze?) · ขนาด/ชนิดที่จำกัดไว้

## 2. การอ่าน (accuracy — สำหรับเป้า auto มากขึ้น)
- easyocr เรียกด้วย language อะไร (มี 'th' + 'en' ไหม) · gpu/cpu · ตั้งค่าอะไรเป็นพิเศษไหม
- **มี image preprocessing ก่อน OCR ไหม** (deskew, contrast, resize, binarize, denoise) — ถ้ามี ทำอะไรบ้าง ถ้าไม่มี บอกว่าไม่มี
- ค่า confidence เก็บ/ใช้ยังไง · threshold conf≥? และ match≥? อยู่บรรทัดไหน (ยืนยันเลข)
- การ "match" เทียบอะไรกับอะไร (ทั้งข้อความ vs รายฟิลด์) · ใช้อัลกอริทึมอะไร (exact / substring / fuzzy?) · normalize ภาษาไทยไหม (ตัดช่องว่าง/วรรณยุกต์)
- ดึงฟิลด์เจาะจงไหม (ชื่อ-สกุล/รหัสนิสิต/ชื่อกิจกรรม/วันที่) หรือ match รวมก้อนเดียว

## 3. PDF
- ตอนนี้ PDF ถูกจัดการยังไง (needs_review เสมอจริงไหม) · มี render เป็นภาพก่อน OCR ไหม

## 4. กันซ้ำ/ปลอม (สำหรับเป้าที่ 2)
- checksum/hash คำนวณจากอะไร (ทั้งไฟล์ไบต์?) · เก็บคอลัมน์ไหน · เทียบขอบเขตไหน (ต่อคน / ทั้งระบบ)
- มี perceptual hash (pHash) หรือจับภาพ "เกือบเหมือน" ไหม (คาดว่าไม่มี — ยืนยัน)
- มีเช็คไหมว่า "เกียรติบัตรใบเดียวกันถูกส่งโดยนิสิตหลายคน" (cross-student duplicate)
- flagged/needs_review ต่างกันยังไงในโค้ด · ใครเห็น flag พวกนี้ในหน้า UI

## 5. สถานะ/สคีมา + ข้อมูลจริง
- ตาราง/คอลัมน์ที่เก็บผล OCR (conf, matched_text, decision, checksum, reviewed_by, reject_reason?) มีอะไรบ้าง
- decision มีกี่สถานะ (auto_approved / needs_review / flagged / rejected?) · มี audit trail ใครตรวจไหม
- query ข้อมูล demo ปัจจุบัน: นับแต่ละ decision มีกี่รายการ · มีตัวอย่างที่ conf/ match เท่าไรบ้าง (ช่วง min/max/เฉลี่ย)

## 6. จุดต่อขยาย
- ถ้าจะเพิ่ม preprocessing / field matching / pHash / pdf-to-image ต้องแตะไฟล์ไหนบ้าง · มี test ครอบ OCR กี่ไฟล์
- dependency ที่มีอยู่แล้ว (opencv, pillow, pymupdf, rapidfuzz, imagehash ...) มีตัวไหนติดตั้งแล้วบ้าง

## รูปแบบรายงาน
- flow ปัจจุบันสั้น ๆ + ตารางจุดสำคัญ (ไฟล์:บรรทัด | ทำอะไร)
- ปิดท้าย: "ตอนนี้ยังไม่มีอะไร (preprocessing? field matching? pHash? pdf-ocr?)" และ "จุดที่เพิ่มได้ง่ายสุด 3 อันดับแรก"

**ห้ามแก้อะไร — รายงานกลับมาก่อน**
