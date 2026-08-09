# Prompts สำหรับ Claude Code — ฟีเจอร์ที่ยังขาดตามรายงาน (ข้อ 6.4–6.9)

วิธีใช้: ก็อปทีละบล็อกไปวางใน Claude Code ทำทีละฟีเจอร์ ทุก prompt สั่งให้สำรวจโค้ดเดิมก่อนและหยุดให้ตรวจก่อน commit

---

## Prompt 1 — ระบบอีเมลแจ้งเตือนอัตโนมัติ (ข้อ 6.4)

```
สำรวจโครงสร้าง backend (FastAPI) ก่อน แล้วเพิ่มระบบส่งอีเมลแจ้งเตือนอัตโนมัติ 2 แบบ:

1) แจ้งเตือนนิสิตกลุ่มเสี่ยง: นิสิตที่ชั่วโมงสะสมใกล้ไม่ครบเกณฑ์ 
   (ดึงจาก gold_student_hours ที่ earned_hours < required_hours และใกล้เส้นตาย)
2) แจ้งประชาสัมพันธ์กิจกรรมที่กำลังเปิดรับสมัคร (approved + start_at ในอนาคต)

ข้อกำหนด:
- เพิ่มโมดูล app/email.py ใช้ SMTP (อ่าน config จาก .env: SMTP_HOST/PORT/USER/PASS/FROM)
- ทำ interface EmailSender แบบเดียวกับ pattern ObjectStorage/LlmClient ที่มีอยู่ 
  โดยมี SmtpEmailSender (ตัวจริง) และ StubEmailSender (ไว้เทส ไม่ส่งจริง)
- เพิ่ม endpoint ให้ admin สั่งส่งได้เอง: POST /notifications/at-risk , POST /notifications/activity/{id}
- เพิ่ม scheduled job (เช่น APScheduler) รันเช็กกลุ่มเสี่ยงอัตโนมัติวันละครั้ง — ถ้ายังไม่มี scheduler ให้ทำเป็น endpoint ก่อนแล้วบอกฉัน
- อีเมลเป็นภาษาไทย มี template ชัดเจน (ชื่อนิสิต, ชั่วโมงที่ขาด, ลิงก์)

เขียน unit test ด้วย StubEmailSender ทำเสร็จหยุดให้ฉันตรวจก่อน commit
```

---

## Prompt 2 — ส่งออกรายงานชั่วโมงเป็น PDF / Excel (ข้อ 6.5)

```
เพิ่มฟังก์ชัน Export รายงานชั่วโมงกิจกรรมสะสม สำรวจ gold_student_hours และ 
gold_dim_student ก่อนว่ามีคอลัมน์อะไร แล้วทำ:

Backend (FastAPI):
- GET /reports/student-hours.xlsx?faculty=&year_level=  → ไฟล์ Excel (ใช้ openpyxl)
- GET /reports/student-hours.pdf?faculty=&year_level=   → ไฟล์ PDF (ใช้ reportlab หรือ weasyprint)
- ข้อมูลต่อแถว: รหัสนิสิต, ชื่อ, คณะ, ชั้นปี, หมวด, ชั่วโมงที่ได้/ต้องการ, สถานะครบ/ไม่ครบ
- กรองตามคณะ/ชั้นปีได้ ผ่าน query param
- สิทธิ์: admin และ staff เท่านั้น

Frontend (Flutter):
- ปุ่ม "ส่งออก PDF" และ "ส่งออก Excel" ในหน้า dashboard/รายงานชั่วโมง 
- กดแล้วดาวน์โหลดไฟล์ (รองรับ Flutter web download)

หัวตาราง/ชื่อไฟล์เป็นภาษาไทย ทำเสร็จหยุดให้ฉันตรวจก่อน commit
```

---

## Prompt 3 — โมดูลนำเข้าแผนกิจกรรมประจำภาคเรียน (ข้อ 6.7)

```
เพิ่มโมดูลให้เจ้าหน้าที่/แอดมิน "นำเข้าแผนการจัดกิจกรรมทั้งภาคเรียน" แบบเป็นชุด 
(bulk import) จากไฟล์ Excel/CSV แทนการสร้างทีละอัน สำรวจ model Activity และ 
endpoint สร้างกิจกรรมเดิมก่อน แล้วทำ:

Backend:
- POST /activities/import  รับไฟล์ .xlsx/.csv (คอลัมน์: ชื่อ, ประเภท, หมวดย่อย, 
  วันเวลา, ชั่วโมง, สถานที่, จำนวนรับ, บังคับ)
- validate ทุกแถว: วันเวลาห้ามย้อนหลัง, หมวดย่อยต้องมีจริง, ชั่วโมง > 0
- แถวที่ผิดให้ return รายงาน error รายแถว (row number + เหตุผล) ไม่ล้มทั้งไฟล์
- แถวที่ผ่าน insert เป็นกิจกรรมสถานะ pending
- ดาวน์โหลด template ไฟล์เปล่าได้: GET /activities/import/template.xlsx

Frontend:
- หน้า/dialog อัปโหลดไฟล์ + แสดงผลสรุป (สำเร็จกี่แถว ผิดกี่แถว พร้อมเหตุผล)

ทำเสร็จหยุดให้ฉันตรวจก่อน commit
```

---

## Prompt 4 — Chatbot โหมดแนะนำเชิงรุกตอนกิจกรรมเต็ม (ข้อ 6.9 ข้อ 4)

```
ต่อยอด chatbot เดิม เพิ่มโหมด "แนะนำเชิงรุก" (Proactive Recommendation) 
สำรวจ logic chatbot เดิม (intent RECOMMEND / RULES / HOURS) และ gold_activity_catalog 
ก่อน แล้วทำ:

เงื่อนไข: เมื่อนิสิตถามสมัคร/สนใจกิจกรรมที่ participant เต็มแล้ว (participant_count >= 
max_participants) ให้ระบบ:
1) แจ้งว่ากิจกรรมนั้นเต็ม
2) วิเคราะห์จาก gold ว่านิสิตยังขาดชั่วโมงหมวดไหน
3) แนะนำกิจกรรมทดแทนที่ยังเปิดรับ (ยังไม่เต็ม + approved + อนาคต) และอยู่ในหมวด
   ที่นับทดแทนกันได้ เรียงตามความเหมาะสม

- ต่อยอดจาก intent เดิม อย่าสร้างระบบใหม่ทั้งชุด
- ถ้าไม่มีกิจกรรมทดแทน ให้ตอบอย่างสุภาพว่ายังไม่มีตอนนี้
- คำตอบภาษาไทย เป็นธรรมชาติ

เขียน test เคสกิจกรรมเต็ม ทำเสร็จหยุดให้ฉันตรวจก่อน commit
```

---

## หมายเหตุก่อนเริ่ม
- ทำทีละ prompt อย่ารวด เพราะแต่ละอันแตะหลายไฟล์
- Prompt 1–3 อาจต้องเพิ่ม dependency (openpyxl, reportlab, APScheduler) — ให้ Claude Code เพิ่มใน requirements และบอกคุณ
- เคลียร์เรื่อง "กฎการนับชั่วโมงตามชั้นปี" กับอาจารย์ก่อน จะได้ทำ Prompt 1/2 ให้ตรงเกณฑ์
