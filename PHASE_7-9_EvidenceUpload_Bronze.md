# สเปก Phase 7–9 สำหรับ Claude Code — ความปลอดภัย, MinIO, อัปโหลดหลักฐาน (Bronze Layer)

> วิธีใช้: วางไฟล์นี้ในโฟลเดอร์โปรเจกต์ แล้วสั่ง Claude Code:
> "อ่าน PHASE_7-9_EvidenceUpload_Bronze.md แล้วทำทีละ Phase เริ่ม Phase 7 หยุดให้ฉันตรวจก่อนไป Phase ถัดไป"
>
> ต่อยอดจาก Phase 1–6 (CRUD + role permissions + ownership + อนุมัติกิจกรรม + หมวดชั่วโมง)
> **ทุกกฎต้องบังคับที่ backend และมี pytest คุมเสมอ**

---

# Phase 7 — อุดช่องโหว่ความปลอดภัย + เติม endpoint ที่ขาด

ทำก่อนเพราะเร็วและสำคัญ

1. **`GET /participations?student_id=X`** — ถ้าผู้เรียกเป็น student ต้อง**บังคับใช้ id ของตัวเองเสมอ** ไม่ว่าจะส่งพารามิเตอร์อะไรมา (ห้ามดูของคนอื่นผ่าน query string)
2. **`POST /participations` (ตัวเต็ม)** — student เรียกไม่ได้ → 403 (ต้องใช้ `/participations/register` เท่านั้น) กันการยัด `hours_earned` / `evidence_status` เอง
3. **ยกเลิกการสมัครของตัวเอง** — student ลบ participation ของตัวเองได้เฉพาะเมื่อ `evidence_status = pending` และยังไม่เช็กอิน; ของคนอื่น → 403; ที่อนุมัติแล้ว → 400
4. **เพิ่ม `GET /students/{id}/hours-summary`** — สำหรับ staff/admin ดูชั่วโมงสะสมของนิสิตรายคน (staff เห็นได้เฉพาะนิสิตที่เข้าร่วมกิจกรรมของตัวเอง); student เรียกของคนอื่น → 403
5. pytest ครอบทุกข้อข้างบน

---

# Phase 8 — ติดตั้ง MinIO + วางรากฐาน Bronze Layer

นี่คือจุดเริ่มต้นจริงของสถาปัตยกรรม Data Lake ตามข้อเสนอโครงงาน

## 8.1 เพิ่ม MinIO ใน docker-compose

- เพิ่ม service `minio` (image `minio/minio`) เปิดพอร์ต `9000` (API) และ `9001` (Console)
- ตั้งค่าผ่าน `.env`: `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `MINIO_ENDPOINT`, `MINIO_BUCKET_BRONZE=bronze`
- ใช้ named volume เก็บข้อมูลให้คงอยู่หลัง restart
- อัปเดต `.env.example` และ README (วิธีเปิด MinIO Console)

## 8.2 โมดูลเชื่อมต่อ MinIO ใน backend

- ใช้ไลบรารี `minio` (หรือ `boto3` แบบ S3-compatible)
- สร้าง `app/storage.py`: ฟังก์ชัน `upload_object()`, `get_object_stream()`, `ensure_bucket()`
- ตอนแอปเริ่มทำงาน ให้สร้าง bucket `bronze` อัตโนมัติถ้ายังไม่มี

## 8.3 หลักการ Bronze Layer (ตามข้อเสนอโครงงาน)

Bronze = **เก็บไฟล์ดิบตามต้นฉบับ ไม่ดัดแปลง** พร้อมบันทึก **timestamp** และ **แหล่งที่มา (data lineage)**

**โครงสร้าง path ใน bucket** (แบ่งตามเวลาเพื่อรองรับการ query ภายหลัง):

```
bronze/evidence/year=<YYYY>/month=<MM>/activity_id=<A>/participation_id=<P>/<uuid>_<ชื่อไฟล์เดิม>
```

**ตารางใหม่ `raw_file`** (metadata ของทุกไฟล์ที่เข้า Bronze):

| ฟิลด์ | ความหมาย |
|---|---|
| `id` | PK |
| `bucket` | ชื่อ bucket (bronze) |
| `object_key` | path เต็มใน MinIO |
| `original_filename` | ชื่อไฟล์ต้นฉบับที่ผู้ใช้อัปโหลด |
| `content_type` | ประเภทไฟล์ (image/jpeg, application/pdf …) |
| `size_bytes` | ขนาดไฟล์ |
| `checksum` | SHA-256 ของไฟล์ (ตรวจความสมบูรณ์ + กันไฟล์ซ้ำ) |
| `source_system` | แหล่งที่มา เช่น `student_upload`, `staff_import` |
| `uploaded_by` | user id ผู้อัปโหลด |
| `ingested_at` | เวลาที่เข้าสู่ Bronze (UTC) |
| `participation_id` | FK อ้างถึงการเข้าร่วมที่เกี่ยวข้อง (nullable) |

> **สำคัญ:** ห้ามแก้ไขหรือลบไฟล์ใน Bronze — เป็นชั้นข้อมูลดิบสำหรับตรวจสอบย้อนกลับ (immutable) ถ้าผู้ใช้อัปโหลดใหม่ ให้เก็บเป็นไฟล์ใหม่อีก object แล้วชี้ให้ participation ใช้ตัวล่าสุด

## 8.4 pytest

- อัปโหลดไฟล์แล้วมี record ใน `raw_file` ครบทุกฟิลด์
- `object_key` ตรงรูปแบบ path ที่กำหนด
- checksum คำนวณถูกต้อง

---

# Phase 9 — ฟีเจอร์อัปโหลดหลักฐานการเข้าร่วม

## 9.1 Backend

1. **`POST /participations/{id}/evidence`** (multipart/form-data)
   - นิสิตอัปโหลดได้**เฉพาะ participation ของตัวเอง** (ของคนอื่น → 403)
   - รับเฉพาะ `image/jpeg`, `image/png`, `application/pdf`; ขนาดไม่เกิน **10 MB** (เกิน → 413 หรือ 400)
   - บันทึกไฟล์ลง MinIO (Bronze) + สร้าง record ใน `raw_file`
   - ตั้ง `evidence_status = pending` ให้อัตโนมัติ (ส่งเข้าคิวรอตรวจ)
   - อัปโหลดซ้ำได้ถ้ายัง pending; ถ้าอนุมัติแล้ว → 400
2. **`GET /participations/{id}/evidence`** — ดาวน์โหลด/ดูไฟล์หลักฐาน
   - **ห้ามเปิด bucket เป็น public** ให้ backend เป็นตัวกลางตรวจสิทธิ์แล้ว stream ไฟล์ออกมา (หรือออก presigned URL อายุสั้น ≤ 5 นาที)
   - สิทธิ์: เจ้าของ participation (student), staff เจ้าของกิจกรรมนั้น, admin เท่านั้น
3. เพิ่มฟิลด์ใน `ParticipationRead`: `has_evidence` (bool) และ `evidence_uploaded_at` เพื่อให้ UI แสดงสถานะได้

## 9.2 Frontend (Flutter Web)

1. **ฝั่งนิสิต** — ในหน้าการเข้าร่วมของตัวเอง ถ้ารายการยัง `pending` ให้มีปุ่ม **"อัปโหลดหลักฐาน"** เลือกไฟล์ภาพ/PDF ได้ พร้อมแสดงสถานะว่าอัปโหลดแล้วหรือยัง
2. **ฝั่ง staff** — ในหน้า "ผู้เข้าร่วมของกิจกรรมนี้" (จาก Phase 4) ให้**กดดูรูปหลักฐานได้** แล้วค่อยกดอนุมัติ/ไม่อนุมัติ — ไม่ใช่อนุมัติแบบไม่เห็นหลักฐานเหมือนตอนนี้
3. แสดง preview รูปภาพในหน้าจอได้เลย (ถ้าเป็น PDF ให้เปิดในแท็บใหม่)

## 9.3 pytest

- นิสิตอัปโหลดของตัวเอง → 201 และไฟล์เข้า MinIO จริง
- นิสิตอัปโหลดให้ participation คนอื่น → 403
- อัปโหลดไฟล์ประเภทไม่รองรับ (เช่น .exe) → 400
- อัปโหลดไฟล์เกิน 10 MB → ถูกปฏิเสธ
- staff เจ้าของกิจกรรมเปิดดูหลักฐานได้ → 200; staff คนอื่น → 403
- อัปโหลดทับหลังอนุมัติแล้ว → 400

---

## เกณฑ์ว่าเสร็จ (acceptance)

- [ ] `docker compose up` ขึ้นครบ: db + backend + **minio**
- [ ] เข้า MinIO Console ที่ `localhost:9001` เห็น bucket `bronze` และเห็นไฟล์ที่อัปโหลดจริง
- [ ] นิสิตอัปโหลดรูปหลักฐานผ่านหน้าเว็บได้ และ staff เปิดดูรูปนั้นก่อนกดอนุมัติได้
- [ ] ทุกไฟล์มี record ใน `raw_file` พร้อม timestamp และ source (data lineage ครบ)
- [ ] pytest ผ่านทั้งหมด

---

## ทำไม Phase นี้สำคัญกับโครงงาน

หลังทำเสร็จ คุณจะตอบกรรมการได้ว่า **"Data Lake อยู่ตรงไหน"** — Bronze Layer ทำงานจริงแล้ว โดยเก็บข้อมูลไร้โครงสร้าง (รูปหลักฐาน/เกียรติบัตร) ที่ระบบฐานข้อมูลเชิงสัมพันธ์แบบเดิมจัดการไม่ได้ พร้อม timestamp และ data lineage ตามที่เขียนไว้ในข้อเสนอ

**ขั้นถัดไปหลังจากนี้ (ยังไม่ต้องทำตอนนี้):** Silver Layer — ประมวลผลรูปด้วย OCR (PaddleOCR/EasyOCR) เพื่อตรวจหลักฐานอัตโนมัติ แล้ว Gold Layer — Star Schema สำหรับแดชบอร์ด
