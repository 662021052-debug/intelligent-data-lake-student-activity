# Prompt สำหรับ Claude Code — รื้อ DB เป็นเกณฑ์แบบมีเวอร์ชัน + โหลดชุดข้อมูลใหม่

อ้างอิงเอกสารออกแบบ `DB_Redesign_ActivityCriteria.md` (รายละเอียดตาราง/คอลัมน์/seed 2567 อยู่ในนั้น)
งานนี้ **ล้างข้อมูลเดิมทิ้งทั้งหมด** แล้วสร้างใหม่ — ทำเป็นเฟส หยุดให้ตรวจทุกเฟส ทุกเฟส test/build ต้องผ่าน

## เตรียมก่อน (ผู้ใช้ทำ)
- วางไฟล์ `ข้อมูล 69.xlsx` ไว้ใน repo เช่น `backend/seed/students_69.xlsx`
- **BACKUP DB ก่อนล้าง**: `docker compose exec db pg_dump -U <user> <db> > backup_before_wipe.sql`

---

## เฟส 1 — Schema ใหม่ (criteria versioning) + ล้างข้อมูลเดิม
สร้างตารางตาม `DB_Redesign` §3: `criteria_set`, `talent`, `learning_unit`, `requirement`, `activity_requirement`
- ปรับ `student`: เพิ่ม `cohort`, `program_type`(default regular), `criteria_set_id` · **รับ student_id 10 หลัก** (ข้อมูลจริงเป็น 10 หลัก ไม่ใช่ 9 — แก้ validation)
- ปรับ `activity`: ใช้ `activity_requirement` (many-to-many) แทน `subcategory_id`
- ปรับ `participation`: เพิ่ม snapshot `learning_unit_id`/`requirement_name`
- Alembic migration (DROP gold views ก่อน batch แล้วสร้างใหม่ตาม pattern เดิม)
- ล้างข้อมูลเดิมในทุกตาราง (นิสิต/กิจกรรม/participation/ไฟล์) ให้ว่าง เริ่มจากศูนย์

หยุดให้ตรวจ

## เฟส 2 — Seed ชุดเกณฑ์
- `learning_unit`: 5 หน่วย (พัฒนาทักษะชีวิต, TSU รับใช้สังคม, ศิลปวัฒนธรรมอาเซียน, พัฒนาคุณธรรมและวินัย, ใฝ่เรียนรู้ตลอดชีวิต)
- `criteria_set`: `legacy` (60 ชม.) + `2567-regular` (60 ชม., counting=ทำตามชั่วโมงต่อรายการ)
- `talent` + `requirement` ของ 2567 ตาม `DB_Redesign` §9 (3 talents, บังคับ/เลือก, ชั่วโมง, หน่วยการเรียนรู้)
- ชุด legacy: แปลงจากโครง 5 หมวด/13 หมวดย่อยเดิมเป็น requirement
- **กฎ Social (PLO3)**: 2 requirement เลือก (สร้างนวัตกรรมสังคม + ผู้ประกอบการ) รวมกันต้อง ≥16 ชม. → ทำเป็น requirement_group ที่ตรวจผลรวมอัตโนมัติ

หยุดให้ตรวจ

## เฟส 3 — โหลดนิสิตจาก Excel
Loader อ่าน `students_69.xlsx` (คอลัมน์: รหัสนิสิต, ชื่อ-สกุล, คณะ, สถานะ) โหลด **ทุกแถว (~2,031 คน)**:
- `student.student_id` = รหัส 10 หลัก · `full_name`, `faculty` จากไฟล์
- `cohort` = 2500 + รหัส 2 ตัวแรก · `criteria_set_id`: เข้า ≥2567 → 2567-regular / ≤2566 → legacy (ไฟล์นี้มี 68,69 = 2567 หมด แต่เขียนกฎให้ทั่วไป)
- `program_type` = regular · สร้าง `user` (role=student) ผูก student ให้ทุกคน (รหัสผ่าน default เดียว hash ไว้)
- เก็บคอลัมน์ "สถานะ" (ผ่าน/ไม่ผ่าน) ไว้ใช้ในเฟส 5

หยุดให้ตรวจ

## เฟส 4 — สร้างกิจกรรม 2567 (จำลอง) + ผูก requirement
- สร้างกิจกรรม approved หลายอันครอบทุก requirement ของ 2567 (พอให้นิสิตเข้าร่วมครบเกณฑ์ได้)
- ผูก `activity_requirement` แต่ละกิจกรรม → requirement ที่ตรง · วันเวลากระจายในปีการศึกษา (บางส่วน upcoming เพื่อโชว์ในหน้าสมัคร)

หยุดให้ตรวจ

## เฟส 5 — สร้าง participation จำลองตามสถานะ (B)
สำหรับนิสิตแต่ละคน อิงคอลัมน์ "สถานะ":
- **ผ่าน** → สร้าง participation (approved, evidence_status=approved) ให้ครบทุกเกณฑ์ของ criteria_set: บังคับครบทุกตัว + เลือกครบชั่วโมงทุก requirement + Social รวม ≥16 → รวม 60 ชม.
- **ไม่ผ่าน** → สร้างให้ **ขาดแบบสุ่ม**: สุ่มเลือก 1–2 requirement ให้ได้ชั่วโมงไม่ครบ (หรือขาดบังคับบางตัว) เพื่อให้ตกเกณฑ์จริง
- `hours_earned` คัดลอกจาก activity.hours ตอน approved (ตาม logic เดิม) · snapshot หน่วย/requirement

หยุดให้ตรวจ

## เฟส 6 — คำนวณ completion ใหม่ + gold views
- เขียน `gold_student_hours` ใหม่: เทียบ earned กับ required ของ **criteria_set ของนิสิตแต่ละคน** (ไม่ใช่ global)
- completed = บังคับครบทุกตัว ∧ เลือกครบทุก requirement ∧ กฎ Social รวม ≥16 (ตรวจอัตโนมัติ)
- อัปเดต dashboard/at-risk/อีเมลกลุ่มเสี่ยง ให้ใช้ completion ใหม่
- ตรวจว่าจำนวน "ผ่าน" ที่ระบบคำนวณ ≈ ตรงกับสถานะในไฟล์ (sanity check)

หยุดให้ตรวจ

## เฟส 7 — เทส + ตรวจจริงบน Postgres
- เทส unit ครอบ: แมปรหัส→criteria_set, completion 3 กรณี (ครบ/ขาดเลือก/ขาดบังคับ), Social combined ≥16
- `docker compose up -d --build backend` + `alembic upgrade head` + รัน loader/seed จริง แล้วเช็ก dashboard มีข้อมูล
- รายงานจำนวน: นิสิต / ผ่าน / กลุ่มเสี่ยง / กิจกรรม

## เริ่มเฟส 1 ก่อน เสร็จหยุดให้ฉันตรวจ อย่าทำรวดทุกเฟส
