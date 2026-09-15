# Prompt สำหรับ Claude Code — OCR เฟส 1: ยกระดับการกันไฟล์ซ้ำ/ปลอม

อ้างอิงผล audit OCR (checksum ปัจจุบันเทียบเฉพาะใบ approved · silver.py:44-59)
ทำเป็นเฟสย่อย หยุดให้ตรวจแต่ละเฟส · ทุกเฟส test/build ต้องผ่าน · **backup Postgres ก่อน migration**

## ปัญหาปัจจุบัน (จาก audit)
- checksum ซ้ำถูกจับเฉพาะเทียบกับใบที่ **approved แล้ว** → ถ้า 2 คนส่งไฟล์เดียวกันตอนทั้งคู่ยัง pending จะไม่โดนจับ
- ไม่แยก "คนละนิสิตส่งใบเดียวกัน" (น่าสงสัยกว่า) ออกจาก "คนเดิมใช้ใบซ้ำข้ามกิจกรรม"
- ไม่เก็บว่าซ้ำกับใบไหน (ไม่มี duplicate_of) → เจ้าหน้าที่เห็นแค่ป้าย "ไฟล์ซ้ำ" ลอย ๆ ตัดสินใจยาก
- เจ้าหน้าที่กดอนุมัติใบ flagged ได้เลยโดยไม่มีการเตือน (participations.py:412-429 ไม่เช็กผล OCR)

**ขอบเขต:** เฟสนี้แตะแค่ตรรกะ dedup + การแสดงผล · **ห้ามแตะ EasyOCR/preprocessing/การนับชั่วโมง/completion/gold**

---

## เฟส 1.1 — backend: ขยายการเทียบซ้ำ + แยกประเภท
แก้ `silver.py:44-59` (จุดเทียบ checksum):
- เทียบ checksum กับ **ทุกใบในระบบที่ยังใช้งาน** (pending + needs_review + auto_approved + approved) ไม่ใช่แค่ approved
  - กันเคส 2 คน pending ไฟล์เดียวกัน: ให้ flag ใบที่มาทีหลัง (เทียบ created_at/id ให้ deterministic) ใบแรกไม่ต้อง flag
- **แยกประเภทซ้ำ** (เก็บเป็น reason):
  - `cross_student` — checksum ซ้ำกับใบของ **นิสิตคนอื่น** (น่าสงสัยสุด)
  - `same_student_reuse` — คนเดิมใช้ไฟล์เดิมกับ **กิจกรรมอื่น**
  - (ไฟล์เดิม+กิจกรรมเดิม = อัปโหลดซ้ำของตัวเอง ไม่ใช่ทุจริต — ไม่ต้อง flag หรือ flag เบา ๆ แล้วแต่ที่เหมาะ)
- ยังตั้ง decision=flagged เหมือนเดิม แต่เพิ่มเหตุผล
- **อย่าเปลี่ยนพฤติกรรมกับ demo เดิม**: 4 กลุ่ม checksum ซ้ำที่มีอยู่ (approved คู่ pending) ยังต้อง flag เหมือนเดิม (จะกลายเป็น cross_student)

หยุดให้ตรวจ

## เฟส 1.2 — schema: เก็บว่าซ้ำกับใบไหน (1 migration)
- เพิ่มคอลัมน์ใน `silver_evidence_ocr` (models.py:466):
  - `duplicate_of_participation_id` (nullable FK) — ชี้ไปใบที่ซ้ำด้วย
  - `duplicate_reason` (nullable enum/str: cross_student / same_student_reuse)
- Alembic migration (nullable ทั้งคู่ ปลอดภัยกับข้อมูลเดิม) · backfill ไม่จำเป็น (ของเก่าปล่อย null)
- เพิ่มใน `SilverEvidenceOcrRead` schema + `frontend/lib/models/ocr_result.dart`
- เทส: ค่าเดิมยังอ่านได้ (null ได้), ใบ flagged ใหม่มี duplicate_of + reason

หยุดให้ตรวจ

## เฟส 1.3 — frontend: แสดงผลให้ตัดสินใจง่าย + กันอนุมัติพลาด
- หน้าตรวจหลักฐาน/OCR: แทนป้าย "ไฟล์ซ้ำ" ลอย ๆ ด้วยข้อความมีบริบท:
  - cross_student → ป้ายแดง "⚠ ซ้ำกับใบของนิสิตคนอื่น: {ชื่อ/รหัส} · กิจกรรม {ชื่อ}"
  - same_student_reuse → ป้ายเหลือง "ใช้ไฟล์เดิมกับกิจกรรม {ชื่อ}"
  - ทำลิงก์ไปดูใบต้นทางได้ถ้าทำง่าย
- **กันอนุมัติพลาด**: เวลาเจ้าหน้าที่/admin กดอนุมัติใบที่ flagged → **ขึ้น dialog ยืนยัน** บอกว่าซ้ำกับอะไร ต้องกดยืนยันอีกครั้งถึงอนุมัติ
  (ไม่บล็อกถาวร เผื่อมีเหตุผลจริง แค่ต้องรับรู้ก่อน) — ฝั่ง backend ปล่อยให้อนุมัติได้เหมือนเดิม การกันอยู่ที่ UX
- นิสิตยังไม่เห็นผล OCR/flag เหมือนเดิม

หยุดให้ตรวจ

## เฟส 1.4 — ทดสอบ + ตรวจจริง
- unit เทส (ครอบให้ครบ):
  - 2 ใบ pending ไฟล์เดียวกัน → ใบหลัง flagged reason=cross_student, ใบแรกไม่ flag
  - คนเดิมไฟล์เดิม กิจกรรมต่างกัน → same_student_reuse
  - ไฟล์ไม่ซ้ำ → ไม่ flag
  - demo 4 กลุ่มเดิม → ยัง flag (cross_student) จำนวนเท่าเดิม
  - อนุมัติใบ flagged ต้องผ่าน dialog ยืนยัน
- ตรวจจริงบน Postgres (backup ก่อน): รัน seed demo → นับ decision เท่าเดิม (auto 11 / needs_review 9 / flagged 4) + flagged มี reason/duplicate_of ครบ
- `flutter test` ธรรมดา + backend test ที่เกี่ยวข้องผ่าน · E2E: หน้าตรวจหลักฐานเห็นป้ายซ้ำมีบริบท + dialog ยืนยันตอนอนุมัติ flagged

## ข้อควรระวัง
- **ห้ามแตะการอ่าน OCR/preprocessing/การนับชั่วโมง** — เฟสนี้เรื่อง dedup อย่างเดียว
- ระวัง performance: การเทียบ checksum กับทุกใบ ควรใช้ index ที่ raw_file.checksum ที่มีอยู่แล้ว (models.py:442) อย่า scan ทั้งตารางแบบ O(n²)
- migration ปลอดภัย (nullable) + backup ก่อนรันบน Postgres จริง

เริ่มเฟส 1.1 ก่อน เสร็จหยุดให้ตรวจ
