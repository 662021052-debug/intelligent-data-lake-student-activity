# Prompt สำหรับ Claude Code — ประเภทหลักฐาน: นิสิตเลือกตอนอัปโหลด · ภาพถ่าย → needs_review เสมอ

**บริบท:** OCR ยืนยันได้แค่ "งานจัดจริง" (จากข้อความบนใบ) แต่ยืนยันตัวตนคนในภาพถ่ายหน้าแบนเนอร์ไม่ได้
→ ให้ **นิสิตเลือกประเภทหลักฐานตอนอัปโหลด** และ **ภาพถ่าย → เข้า needs_review เสมอ ไม่ auto-approve** (ให้คนตรวจ)

ทำเป็นเฟส หยุดให้ตรวจแต่ละเฟส · ทุกเฟส test/build ผ่าน · backup Postgres ก่อน migration
**ห้ามแตะ**: การนับชั่วโมง/completion/gold/resolver · logic dedup (checksum/pHash) เดิม — ยังต้องทำงานกับภาพถ่ายด้วย

## หลักการ
- เพิ่มฟิลด์ประเภทหลักฐาน: **certificate** (เกียรติบัตร/ใบรับรอง) · **photo** (ภาพถ่ายกิจกรรม/หน้าแบนเนอร์) · **other** (อื่น ๆ)
- **certificate** → เข้ากระบวนการ OCR auto-approve เดิม (conf/match ตามเกณฑ์)
- **photo / other** → **บังคับ needs_review เสมอ** ต่อให้ OCR score สูงก็ไม่ auto (เพราะยืนยันตัวตนไม่ได้)
- ยังรัน OCR ให้ (อ่านข้อความแบนเนอร์ไว้ให้คนตรวจอ้างอิง) และยังรัน checksum/pHash dedup (ภาพแชร์กันต้องยังจับได้)
- ไม่มีช่องโหว่: ภาพถ่ายที่ติดผิดเป็น certificate ก็ match ไม่ผ่าน (ไม่มีชื่อบนภาพ) → review อยู่ดี · cert ติดผิดเป็น photo → แค่เข้า review ไม่เสียหาย

---

## เฟส 1 — backend: ฟิลด์ประเภท + บังคับ photo → needs_review
- เพิ่ม enum `EvidenceKind` (certificate/photo/other) + คอลัมน์ `raw_file.evidence_kind` (หรือที่เหมาะกับ flow อัปโหลด) · Alembic migration (nullable)
  - **backfill legacy = certificate** (แถวเก่าคงพฤติกรรมเดิม ไม่เปลี่ยนคำตัดสินในอดีต) · ถ้า null ตอนประมวลผลให้ถือเป็น certificate
- รับค่า evidence_kind ตอน `POST /participations/{id}/evidence` (form field) · validate เป็น 1 ใน 3 ค่า
- ใน `silver.py` (จุดตัดสิน): ถ้า `evidence_kind in (photo, other)` → **บังคับ decision = needs_review** (ไม่เข้า auto_approved) แม้ conf/match ผ่าน
  - แต่ยังรัน OCR + checksum/pHash เหมือนเดิม (flagged ถ้าซ้ำก็ยัง flagged)
- เทส: photo + match สูง → needs_review (ไม่ auto) · certificate + match สูง → auto เหมือนเดิม · photo ที่ไฟล์ซ้ำ → ยัง flagged · legacy null → certificate behavior

หยุดให้ตรวจ

## เฟส 2 — frontend: ตัวเลือกตอนอัปโหลด + ป้ายในหน้าตรวจ
- ฟอร์มอัปโหลดหลักฐาน (ฝั่งนิสิต + ที่แอดมินอัปแทนได้): เพิ่มตัวเลือก **"ประเภทหลักฐาน"** (required):
  - ○ เกียรติบัตร / ใบรับรอง  ○ ภาพถ่ายกิจกรรม (หน้าแบนเนอร์/สถานที่)  ○ อื่น ๆ
  - มีข้อความช่วย: "ภาพถ่ายจะถูกส่งให้เจ้าหน้าที่ตรวจ ไม่อนุมัติอัตโนมัติ"
- หน้าตรวจหลักฐาน/OCR: แสดงป้ายประเภทชัดเจน เช่น "📷 ภาพถ่ายกิจกรรม — ต้องตรวจด้วยตา" เพื่อให้เจ้าหน้าที่รู้ว่าทำไมเข้า review
- เทส: ฟอร์มส่ง evidence_kind ในคำขอ · ป้ายแสดงถูกตามประเภท

หยุดให้ตรวจ

## เฟส 3 — demo fixture + ตรวจจริง
- seed_evidence_demo: เพิ่มใบประเภท photo 1 ใบ (มีข้อความแบนเนอร์ตรงกิจกรรม match สูง) → ต้องได้ **needs_review** ไม่ใช่ auto (พิสูจน์กฎ)
- ตรวจจริงบน Postgres (backup ก่อน): reseed → photo ใบนั้น needs_review แม้ match สูง · certificate เดิม auto เท่าเดิม · completion 2,031 ไม่เพี้ยน
- `flutter test` + backend test ผ่าน · E2E: อัปโหลดเลือก "ภาพถ่าย" → เข้า review + ป้ายแสดงถูก

หยุดให้ตรวจ

## ข้อควรระวัง
- อย่าให้ photo หลุด auto ทางอ้อม (เช็กในจุดตัดสินให้ครอบทุกทางที่ตั้ง auto_approved)
- QR check-in เป็นคนละ flow (หลักฐานการเข้าร่วมที่แข็งกว่า) — ไม่ต้องแตะ
- migration nullable + backfill certificate + backup ก่อน Postgres จริง

เริ่มเฟส 1 ก่อน เสร็จหยุดให้ตรวจ
