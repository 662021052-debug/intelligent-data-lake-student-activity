# Prompt สำหรับ Claude Code — OCR เฟส 3: pHash (ภาพเกือบเหมือน) + รองรับ PDF

อ้างอิงผล audit + เฟส 1 (dedup ด้วย checksum เป๊ะ) ที่ทำแล้ว
ทำเป็นเฟสย่อย หยุดให้ตรวจแต่ละเฟส · ทุกเฟส test/build ผ่าน · **backup Postgres ก่อน migration**

## 2 เป้าของเฟสนี้
- **3A pHash**: checksum จับได้แค่ไฟล์เหมือนเป๊ะทุกไบต์ → ครอป/บีบอัด/แก้ 1 พิกเซลก็เลี่ยงได้ · เพิ่ม perceptual hash จับ "ภาพเกือบเหมือน"
- **3B PDF**: ตอนนี้ PDF เด้ง needs_review เสมอ (silver.py:62-71 คืน "",0) · render เป็นภาพแล้ว OCR จริง

**ห้ามแตะ**: การนับชั่วโมง/completion/gold/resolver · logic checksum เดิม (เฟส 1) ให้คงไว้ pHash เป็น "ชั้นที่สอง"

---

## เฟส 3A.1 — pHash schema + คำนวณตอนอัปโหลด
- เพิ่ม dependency `imagehash` (Pillow มีแล้ว) ใน requirements.txt
- เพิ่มคอลัมน์ `RawFile.phash` (nullable str/64-bit, models.py) + Alembic migration (nullable ปลอดภัย ไม่ backfill)
- คำนวณ pHash ตอนรับไฟล์ (participations.py:526-549) **เฉพาะไฟล์ภาพ** (PDF ข้ามไปก่อน จะทำใน 3B) · เก็บลง raw_file.phash
- เลือก algorithm: `imagehash.phash` (DCT-based, ทนการบีบอัด/ปรับขนาด) hash size 8 (64 บิต)
- เทส: อัปโหลดภาพ → มี phash · ภาพเดิมที่บีบอัด JPEG ใหม่ → phash ใกล้กัน (Hamming น้อย) · ภาพคนละใบ → Hamming ห่าง

หยุดให้ตรวจ

## เฟส 3A.2 — จับภาพเกือบเหมือนใน dedup
- ใน `silver.py` (จุด find_duplicate ของเฟส 1): **หลังเช็ก checksum เป๊ะไม่เจอ** ให้เช็ก pHash ต่อ
  - เทียบ Hamming distance ของ phash กับใบภาพอื่น (active + rejected เหมือนเฟส 1) · **threshold ตั้งใน config.py** (เริ่ม ≤ 6 บิต จาก 64 ปรับได้)
  - เจอใกล้กว่า threshold → flagged เหมือน checksum ซ้ำ · ใช้ DuplicateReason เดิม (cross_student/same_student_reuse/matches_rejected) ตามเจ้าของ/สถานะใบต้นทาง
  - **แยก "เป๊ะ" กับ "คล้าย"**: เพิ่มฟิลด์ `match_kind` (exact / near) ในผล OCR (คอลัมน์ใหม่ nullable + migration รวมกับ 3A.1 ได้) เพื่อให้ UI บอกต่างกัน
  - ลำดับ: checksum เป๊ะมาก่อนเสมอ · ถ้าเป๊ะไม่เจอค่อยดู pHash · ถ้า pHash เจอหลายใบ เลือกตามลำดับความสำคัญเดิม (cross > same > rejected) และใกล้สุด
- **performance**: pHash เทียบด้วย Hamming ใช้ index ไม่ได้ตรง ๆ → สำหรับสเกลนี้ scan เฉพาะ RawFile ที่เป็นภาพและมี phash พอ · จำกัด candidate ตามเหมาะ (เช่นเฉพาะที่ยัง active/rejected) · **รายงานถ้าเห็นว่าจะช้าตอนสเกลใหญ่** (ไม่ต้องแก้ตอนนี้ แค่เตือน)
- เทส: ภาพครอป/บีบอัดของนิสิตคนอื่น → flagged cross_student + match_kind=near · ภาพไม่เกี่ยว → ไม่ flag · checksum เป๊ะยังทำงานเหมือนเดิม (match_kind=exact)

หยุดให้ตรวจ

## เฟส 3B — รองรับ PDF (render เป็นภาพแล้ว OCR)
- เพิ่ม dependency `pymupdf` (fitz) ใน requirements.txt + rebuild image
- ใน `silver.py:62-71` (_extract_text): ถ้าเป็น PDF → render หน้าเป็นภาพด้วย PyMuPDF (DPI ~200) แล้วส่งเข้า EasyOCR
  - จำกัดจำนวนหน้า (เช่น 3 หน้าแรก) กันช้า · รวมข้อความทุกหน้า · conf เฉลี่ยเหมือนภาพ
  - ถ้า render ล้ม → คืน ("",0) แบบเดิม (needs_review) ไม่ให้ crash
- (option) pHash หน้าแรกของ PDF ด้วย เพื่อจับเคสส่งใบเดียวกันทั้งแบบ PDF และ JPG — ถ้าทำง่ายก็ทำ ถ้าไม่ก็เว้นไว้ก่อน แล้วรายงาน
- แก้เทสเดิม `test_silver_ocr.py:135 test_non_image_skips_ocr` ให้สะท้อนว่า PDF ถูก OCR แล้ว (ไม่ skip)
- เทส: PDF ที่มีข้อความตรงกับนิสิต/กิจกรรม → ได้ match score เหมือนภาพ (ไม่เด้ง needs_review อัตโนมัติ) · PDF เสีย → needs_review ไม่ crash

หยุดให้ตรวจ

## เฟส 3C — frontend + demo fixtures + ตรวจจริง
- frontend: ในแถบ/ป้ายซ้ำ (duplicate_notice ของเฟส 1) บอกต่างระหว่าง **"ไฟล์ซ้ำ" (exact)** กับ **"ภาพคล้ายกันมาก" (near)** ตาม match_kind · สี/ความรุนแรงตามเหตุผลเดิม
- demo fixtures (เพื่อทดสอบจริง): เพิ่มใน seed_evidence_demo ให้มี
  - ใบภาพ near-duplicate (เอาใบเดิมมาครอป/บีบอัดใหม่) ของนิสิตคนอื่น → ต้องโดน flag near + cross_student
  - ใบ PDF 1 ใบที่ข้อความตรง → ต้องถูก OCR และได้ decision ตามคะแนน (ไม่ใช่ needs_review อัตโนมัติ)
- ตรวจจริงบน Postgres (backup ก่อน): reseed → นับ decision, ยืนยัน near-dup โดน flag + PDF มีข้อความ OCR · completion 2,031 คนไม่เพี้ยน
- `flutter test` ธรรมดา + backend test ผ่าน · E2E: หน้าตรวจเห็นป้าย "ภาพคล้ายกันมาก" และ PDF มีผล OCR

หยุดให้ตรวจ

## ข้อควรระวังรวม
- pHash เป็นชั้นเสริม **ห้ามลดทอน checksum เป๊ะ** ของเฟส 1
- threshold pHash ตั้งใน config ปรับได้ · เริ่มเข้ม (≤6) กัน false positive ใบที่หน้าตาเทมเพลตเหมือนกันแต่คนละคน — **รายงานถ้าเจอว่าใบเทมเพลตเดียวกัน (เกียรติบัตรฟอร์มเดียวกัน) ชนกันเยอะ** อาจต้องเทียบ OCR text ประกอบ
- migration nullable + backup ก่อนรัน Postgres จริง
- ไม่แตะการนับชั่วโมง/completion/gold

เริ่มเฟส 3A.1 ก่อน เสร็จหยุดให้ตรวจ
