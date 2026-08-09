# สเปกระบบสำหรับสร้าง Diagram
> **Intelligent Data Lake for Student Activity Participation Tracking**
> ระบบติดตามการเข้าร่วมกิจกรรมเสริมหลักสูตรของนิสิต มหาวิทยาลัยทักษิณ
>
> เอกสารนี้รวบรวมข้อมูลทั้งหมดที่จำเป็นสำหรับการเขียน **Use Case Diagram / ER Diagram / Class Diagram / Sequence Diagram**
> ข้อมูลทุกส่วนสกัดจากซอร์สโค้ดจริง (backend/app, frontend/lib) ไม่ใช่การคาดเดา

---

## 0. ภาพรวมระบบ (System Context)

ระบบบริหารจัดการและติดตาม "ชั่วโมงกิจกรรมเสริมหลักสูตร" ของนิสิต โดยใช้สถาปัตยกรรม **Data Lake แบบ Medallion (Bronze → Silver → Gold)** ร่วมกับ **AI** 2 ส่วน คือ OCR ตรวจใบประกาศอัตโนมัติ และ Chatbot ตอบคำถามนิสิต

### Tech Stack

| ส่วน | เทคโนโลยี |
|---|---|
| Frontend | Flutter Web (Dart), Material 3, ภาษาไทย |
| Backend | Python 3 + FastAPI + SQLModel (SQLAlchemy + Pydantic) |
| Database | PostgreSQL 16 (prod/docker) / SQLite (dev, test) |
| Object Storage | MinIO (S3-compatible) — bucket `bronze` |
| Auth | JWT (HS256) + bcrypt (passlib) + Role-based Access Control |
| OCR | EasyOCR (ภาษาไทย+อังกฤษ, CPU) — สลับเป็น stub ได้ |
| LLM | Google Gemini (`gemini-flash-latest`) — สลับเป็น stub ได้ |
| Vector Store | pgvector (prod) / in-memory cosine (dev, test) |
| Migration | Alembic |
| Deploy | Docker Compose (db + minio + backend) |

### สถาปัตยกรรม Medallion (ชั้นข้อมูล)

```
[นิสิตอัปโหลดใบประกาศ]
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│ BRONZE — ข้อมูลดิบ immutable                              │
│  • ไฟล์จริงเก็บใน MinIO bucket "bronze"                    │
│    path: evidence/year=YYYY/month=MM/activity_id=A/        │
│          participation_id=P/<uuid>_<filename>              │
│  • metadata + lineage เก็บในตาราง raw_file                 │
│    (checksum SHA-256, source_system, uploaded_by,          │
│     ingested_at, content_type, size_bytes)                 │
│  • อัปโหลดใหม่ = สร้าง object ใหม่เสมอ ไม่ทับของเดิม        │
└──────────────────────────────────────────────────────────┘
        │  (BackgroundTask)
        ▼
┌──────────────────────────────────────────────────────────┐
│ SILVER — ข้อมูลที่ทำความสะอาด/ตรวจสอบแล้ว                  │
│  • OCR อ่านข้อความจากใบประกาศ (EasyOCR th+en)              │
│  • ตรวจไฟล์ซ้ำจาก checksum                                 │
│  • คำนวณ match_score เทียบชื่อนิสิต/ชื่อกิจกรรม/ปี (fuzzy)   │
│  • ตัดสิน: auto_approved / needs_review / flagged           │
│  • เก็บผลลงตาราง silver_evidence_ocr                       │
└──────────────────────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────────────────────┐
│ GOLD — Star Schema พร้อมวิเคราะห์ (SQL Views ขึ้นต้น gold_)│
│  fact: gold_fact_participation (grain = participation      │
│        ที่ approved แล้วเท่านั้น)                           │
│  dim : gold_dim_student / gold_dim_activity /              │
│        gold_dim_hour_category / gold_dim_subcategory /     │
│        gold_dim_date                                       │
│  mart: gold_student_hours / gold_activity_catalog          │
│  • Dashboard และ Chatbot อ่านจากชั้นนี้เท่านั้น              │
│    ห้ามแตะตาราง operational โดยตรง                          │
└──────────────────────────────────────────────────────────┘
        │                              │
        ▼                              ▼
 [Executive Dashboard]          [AI Chatbot: RAG + Text-to-SQL]
```

---

# 1. ข้อมูลสำหรับ USE CASE DIAGRAM

## 1.1 Actors

| Actor | คำอธิบาย | ผูกกับ Student record |
|---|---|---|
| **นิสิต (Student)** | ล็อกอินด้วยรหัสนิสิต 9 หลัก ดูกิจกรรม สมัคร ส่งหลักฐาน ดูชั่วโมงตัวเอง ถามแชตบอต | ต้องผูก (`User.student_id` ไม่เป็น null) |
| **เจ้าหน้าที่ (Staff)** | สร้าง/แก้กิจกรรม (ต้องรออนุมัติ), ตรวจหลักฐานเฉพาะกิจกรรมที่ตนสร้าง | ไม่ผูก |
| **ผู้ดูแลระบบ (Admin)** | สิทธิ์สูงสุด: จัดการนิสิต/ผู้ใช้, อนุมัติกิจกรรม, ดู Dashboard, refresh Gold layer | ไม่ผูก |
| **‹‹system›› OCR Engine** | Actor รอง — ประมวลผลใบประกาศอัตโนมัติหลังอัปโหลด (EasyOCR) | - |
| **‹‹system›› LLM / Gemini** | Actor รอง — สร้างคำตอบ RAG และแปลงคำถามเป็น SQL | - |
| **‹‹system›› MinIO Object Storage** | Actor รอง — เก็บ/ดึงไฟล์หลักฐานชั้น Bronze | - |

> หมายเหตุ: Staff และ Admin **สืบทอด (generalization)** use case ส่วนใหญ่ของกลุ่ม "ผู้จัดการข้อมูล" ได้ — วาดเป็นลูกศร generalization จาก Admin → Staff ก็ได้ แต่ Admin มี use case พิเศษเพิ่มอีกชุด

## 1.2 Use Cases แยกตาม Actor

### กลุ่มร่วม (ทุก role)
| ID | Use Case | หมายเหตุ |
|---|---|---|
| UC-01 | เข้าสู่ระบบ (Login) | `POST /auth/login` → JWT |
| UC-02 | ออกจากระบบ (Logout) | ฝั่ง client ล้าง token |
| UC-03 | ดูรายการกิจกรรม | นิสิตเห็นเฉพาะที่ approved / staff เห็นเฉพาะที่ตนสร้าง / admin เห็นทั้งหมด |
| UC-04 | ดูปฏิทินกิจกรรม | หน้าเดียวใช้ได้ทั้ง 3 role |
| UC-05 | ค้นหา (live search) | มีในทุกหน้าที่มีรายการ |

### นิสิต (Student)
| ID | Use Case | Endpoint |
|---|---|---|
| UC-10 | สมัครเข้าร่วมกิจกรรมด้วยตนเอง | `POST /participations/register` |
| UC-11 | ยกเลิกการสมัคร | `DELETE /participations/{id}` (ทำได้เฉพาะยังไม่เช็กอิน/ยังไม่อนุมัติ) |
| UC-12 | อัปโหลดหลักฐานการเข้าร่วม | `POST /participations/{id}/evidence` — **‹‹include›› UC-30 ประมวลผล OCR** |
| UC-13 | ดูหลักฐานที่อัปโหลดไปแล้ว | `GET /participations/{id}/evidence` |
| UC-14 | ดูประวัติการเข้าร่วมของตนเอง | `GET /participations` (กรองอัตโนมัติเป็นของตัวเอง) |
| UC-15 | ดูแดชบอร์ดชั่วโมงของฉัน | `GET /students/me/hours-summary` |
| UC-16 | ถามผู้ช่วยอัจฉริยะ (Chatbot) | `POST /chatbot/ask` — **‹‹extend›› UC-40/41/42** |

### เจ้าหน้าที่ (Staff)
| ID | Use Case | Endpoint |
|---|---|---|
| UC-20 | สร้างกิจกรรม (สถานะ pending รออนุมัติ) | `POST /activities` |
| UC-21 | แก้ไขกิจกรรมของตน (แก้แล้วกลับเป็น pending) | `PUT /activities/{id}` |
| UC-22 | ลบกิจกรรมของตน | `DELETE /activities/{id}` |
| UC-23 | บันทึกผู้เข้าร่วมกิจกรรมของตน | `POST /participations` |
| UC-24 | ดูรายชื่อผู้เข้าร่วมกิจกรรมของตน | `GET /activities/{id}/participations` |
| UC-25 | อนุมัติ/ปฏิเสธหลักฐานการเข้าร่วม | `PUT /participations/{id}` (evidence_status) |
| UC-26 | สั่งประมวลผล OCR ใหม่ (re-run) | `POST /participations/{id}/evidence/process` |
| UC-27 | ดูผลตรวจ OCR (หน้า OCR Review) | `GET /participations/{id}/ocr` |
| UC-28 | ดูสรุปชั่วโมงของนิสิตที่ร่วมกิจกรรมตน | `GET /students/{id}/hours-summary` |

### ผู้ดูแลระบบ (Admin) — ได้ทุก use case ของ Staff + เพิ่ม
| ID | Use Case | Endpoint |
|---|---|---|
| UC-50 | จัดการข้อมูลนิสิต (CRUD) | `POST/PUT/DELETE /students` |
| UC-51 | สร้างผู้ใช้และกำหนดสิทธิ์ | `POST /auth/register` |
| UC-52 | จัดการผู้ใช้ (แก้ role/รหัสผ่าน, ลบ) | `GET/PUT/DELETE /auth/users` |
| UC-53 | อนุมัติกิจกรรมที่ staff เสนอ | `PATCH /activities/{id}/approve` |
| UC-54 | ดูแดชบอร์ดผู้บริหาร (KPI/กราฟ/กลุ่มเสี่ยง) | `GET /dashboard/*` |
| UC-55 | รีเฟรช Gold Layer | `POST /gold/refresh` |
| UC-56 | อัปโหลดหลักฐานแทนนิสิต | `POST /participations/{id}/evidence` |

### Use Case ของระบบ (‹‹include›› / ‹‹extend››)
| ID | Use Case | ความสัมพันธ์ |
|---|---|---|
| UC-30 | ประมวลผล OCR ใบประกาศ (Silver) | ‹‹include›› ใน UC-12, UC-26 |
| UC-31 | ตรวจจับไฟล์หลักฐานซ้ำ (checksum) | ‹‹include›› ใน UC-30 |
| UC-32 | คำนวณคะแนนความตรงกัน (match score) | ‹‹include›› ใน UC-30 |
| UC-33 | อนุมัติอัตโนมัติเมื่อผ่านเกณฑ์ | ‹‹extend›› จาก UC-30 |
| UC-40 | ตอบคำถามเกณฑ์ด้วย RAG | ‹‹extend›› จาก UC-16 (intent = RULES) |
| UC-41 | ตอบด้วย SQL ที่ระบบเขียนไว้ (parameterized) | ‹‹extend›› จาก UC-16 (intent = HOURS/MISSING/OPEN/REQUIRED/RECOMMEND) |
| UC-42 | ตอบด้วย LLM Text-to-SQL + ตรวจความปลอดภัย SQL | ‹‹extend›› จาก UC-16 (intent = GENERAL) |

## 1.3 ตารางสิทธิ์ (Permission Matrix) — ใช้ตรวจความถูกต้องของ Use Case Diagram

| การกระทำ | Student | Staff | Admin |
|---|:---:|:---:|:---:|
| ดูนิสิต | ✅ | ✅ | ✅ |
| สร้าง/แก้/ลบ นิสิต | ❌ | ❌ | ✅ |
| ดูกิจกรรม | ✅ (เฉพาะ approved) | ✅ (เฉพาะที่ตนสร้าง) | ✅ (ทั้งหมด) |
| สร้าง/แก้/ลบ กิจกรรม | ❌ | ✅ (ของตน, กลับเป็น pending) | ✅ (approved ทันที) |
| อนุมัติกิจกรรม | ❌ | ❌ | ✅ |
| สมัครกิจกรรมเอง | ✅ | ❌ | ❌ |
| สร้าง participation ให้คนอื่น | ❌ | ✅ (กิจกรรมของตน) | ✅ |
| อัปโหลดหลักฐาน | ✅ (ของตน) | ❌ | ✅ |
| อนุมัติหลักฐาน | ❌ | ✅ (กิจกรรมของตน) | ✅ |
| สั่งรัน OCR | ❌ | ✅ (กิจกรรมของตน) | ✅ |
| ดู Dashboard ผู้บริหาร | ❌ | ❌ | ✅ |
| จัดการผู้ใช้ | ❌ | ❌ | ✅ |
| ใช้ Chatbot | ✅ | ❌ | ❌ |

---

# 2. ข้อมูลสำหรับ ER DIAGRAM

## 2.1 ตารางหลัก (Operational / OLTP)

### `student`
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK**, autoincrement |
| student_id | VARCHAR | UNIQUE, INDEX (รหัสนิสิต 9 หลัก เช่น 662021052) |
| full_name | VARCHAR | NOT NULL |
| faculty | VARCHAR | NOT NULL (7 คณะ) |
| major | VARCHAR | NOT NULL |
| year_level | INTEGER | NOT NULL (1–4) |
| status | ENUM StudentStatus | `active` \| `inactive` — default `active` |

### `user`
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK** |
| username | VARCHAR | UNIQUE, INDEX |
| hashed_password | VARCHAR | NOT NULL (bcrypt) |
| role | ENUM UserRole | `student` \| `staff` \| `admin` — default `student` |
| student_id | INTEGER | **FK → student.id**, NULLABLE (บังคับมีค่าเมื่อ role=student, ต้อง null เมื่อ staff/admin) |

### `hourcategory` (หมวดชั่วโมงหลัก — 5 หมวด รวม 60 ชม.)
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK** |
| name | VARCHAR | NOT NULL |
| required_hours | FLOAT | NOT NULL |

### `hoursubcategory` (กิจกรรมย่อยในหมวด)
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK** |
| category_id | INTEGER | **FK → hourcategory.id**, NOT NULL |
| name | VARCHAR | NOT NULL |
| required_hours | FLOAT | NOT NULL |

### `activity`
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK** |
| name | VARCHAR | NOT NULL |
| activity_type | VARCHAR | NOT NULL (กีฬา / อบรม-สัมมนา / จิตอาสา / ฯลฯ) |
| is_required | BOOLEAN | default false (กิจกรรมบังคับ) |
| max_participants | INTEGER | NOT NULL, **> 0** |
| start_at | DATETIME | NOT NULL |
| location | VARCHAR | NOT NULL |
| hours | FLOAT | default 0, ตอนสร้างต้อง **> 0** — เป็น single source of truth ของชั่วโมงที่จะได้ |
| subcategory_id | INTEGER | **FK → hoursubcategory.id**, NULLABLE ในตาราง แต่บังคับตอนสร้าง |
| created_by | INTEGER | **FK → user.id**, NULLABLE |
| approval_status | ENUM ApprovalStatus | `pending` \| `approved` — default `pending` |
| approved_by | INTEGER | **FK → user.id**, NULLABLE |
| approved_at | DATETIME | NULLABLE |

### `participation` (ตารางเชื่อม student ↔ activity + สถานะหลักฐาน)
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK** |
| student_id | INTEGER | **FK → student.id**, INDEX, NOT NULL |
| activity_id | INTEGER | **FK → activity.id**, INDEX, NOT NULL |
| check_in_time | DATETIME | NULLABLE |
| hours_earned | FLOAT | default 0 — **ระบบคำนวณเท่านั้น** (คัดลอกจาก `activity.hours` ตอนอนุมัติ, กลับเป็น 0 เมื่อ pending/rejected) |
| evidence_status | ENUM EvidenceStatus | `pending` \| `approved` \| `rejected` — default `pending` |

> Business rule: หนึ่งนิสิตสมัครกิจกรรมเดียวกันได้ครั้งเดียว (ตรวจในโค้ด `register_self`)

### `raw_file` — **ชั้น Bronze (metadata + data lineage)**
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK** |
| bucket | VARCHAR | NOT NULL (`bronze`) |
| object_key | VARCHAR | NOT NULL (path ใน MinIO) |
| original_filename | VARCHAR | NOT NULL |
| content_type | VARCHAR | NOT NULL (image/jpeg, image/png, application/pdf) |
| size_bytes | INTEGER | NOT NULL (≤ 10 MB) |
| checksum | VARCHAR | INDEX — SHA-256 ใช้ตรวจ integrity + ไฟล์ซ้ำ |
| source_system | VARCHAR | NOT NULL (`student_upload`, `staff_import`) |
| uploaded_by | INTEGER | **FK → user.id**, NULLABLE |
| ingested_at | DATETIME | default now (UTC) |
| participation_id | INTEGER | **FK → participation.id**, INDEX, NULLABLE |

### `silver_evidence_ocr` — **ชั้น Silver (ผล OCR)**
| คอลัมน์ | ชนิด | ข้อจำกัด |
|---|---|---|
| id | INTEGER | **PK** |
| raw_file_id | INTEGER | **FK → raw_file.id**, INDEX, NOT NULL (ไฟล์ต้นทาง Bronze) |
| participation_id | INTEGER | **FK → participation.id**, INDEX, NULLABLE |
| extracted_text | TEXT | default '' |
| ocr_confidence | FLOAT | default 0.0 (0–1) |
| match_score | FLOAT | default 0.0 (0–1) |
| decision | ENUM OcrDecision | `auto_approved` \| `needs_review` \| `flagged` — default `needs_review` |
| is_duplicate | BOOLEAN | default false |
| processed_at | DATETIME | default now (UTC) |

## 2.2 ความสัมพันธ์ (Relationships / Cardinality)

```
student      1 ──── 0..1  user                 (user.student_id → student.id)
student      1 ──── 0..*  participation        (participation.student_id)
activity     1 ──── 0..*  participation        (participation.activity_id)
hourcategory 1 ──── 1..*  hoursubcategory      (hoursubcategory.category_id)
hoursubcategory 1 ── 0..* activity             (activity.subcategory_id)
user         1 ──── 0..*  activity  [created_by]   (ผู้สร้างกิจกรรม)
user         1 ──── 0..*  activity  [approved_by]  (ผู้อนุมัติกิจกรรม)
participation 1 ─── 0..*  raw_file             (raw_file.participation_id) ← Bronze append-only
user         1 ──── 0..*  raw_file  [uploaded_by]
raw_file     1 ──── 0..*  silver_evidence_ocr  (silver_evidence_ocr.raw_file_id)
participation 1 ─── 0..*  silver_evidence_ocr  (silver_evidence_ocr.participation_id)
```

**สรุปเป็นประโยค**
- `participation` คือ associative entity ที่แปลงความสัมพันธ์ M:N ระหว่าง `student` กับ `activity` พร้อมแอตทริบิวต์เพิ่ม (ชั่วโมงที่ได้, สถานะหลักฐาน, เวลาเช็กอิน)
- หนึ่ง participation มี raw_file ได้หลายไฟล์ (Bronze append-only — อัปโหลดใหม่ไม่ทับของเดิม) ระบบใช้ไฟล์ล่าสุดเสมอ
- หนึ่ง raw_file มีผล OCR ได้หลายครั้ง (รันซ้ำได้) ระบบใช้ผลล่าสุด (`id` มากสุด)

## 2.3 Gold Layer — Star Schema (SQL Views, ไม่ใช่ตารางจริง)

ถ้าต้องวาด **Dimensional Model / Star Schema Diagram** แยกอีกใบ ใช้ผังนี้:

```
                    gold_dim_date
                    (date_key PK, full_date, year,
                     month, semester, academic_year)
                            │
gold_dim_student            │            gold_dim_activity
(student_key PK,            │            (activity_key PK, name,
 student_code, full_name,   │             activity_type, subcategory_key,
 faculty, major,            │             hours, max_participants,
 year_level, status)        │             approval_status, created_by, date_key)
        │                   │                   │
        └───────────┐       │       ┌───────────┘
                    ▼       ▼       ▼
            ┌─────────────────────────────────┐
            │  gold_fact_participation        │  ← FACT
            │  grain: 1 participation ที่      │
            │         evidence_status='approved'│
            │  participation_id (PK degen.)    │
            │  student_key   FK                │
            │  activity_key  FK                │
            │  subcategory_key FK              │
            │  date_key      FK                │
            │  hours_earned  (measure)         │
            │  evidence_status                 │
            └─────────────────────────────────┘
                            ▲
                            │
                  gold_dim_subcategory
                  (subcategory_key PK, category_key FK,
                   name, required_hours)
                            ▲
                            │
                  gold_dim_hour_category
                  (category_key PK, name, required_hours)
```

**Data Mart / Ready views (ไม่ใช่ dim/fact แต่ให้ระบุในไดอะแกรมได้)**
- `gold_student_hours(student_key, student_code, full_name, faculty, year_level, category_key, category_name, required_hours, earned_hours, completed)` — CROSS JOIN นิสิต × หมวด จึงมีแถวครบทุกหมวดแม้ยังไม่ได้ชั่วโมงเลย
- `gold_activity_catalog(activity_key, name, activity_type, is_required, hours, max_participants, approval_status, start_at, date_key, subcategory_key, subcategory_name, category_key, category_name, participant_count)` — แคตตาล็อกกิจกรรมสาธารณะสำหรับ Chatbot

**กติกาสำคัญ**: fact นับเฉพาะ `evidence_status = 'approved'` เท่านั้น / views ถูก DROP+CREATE ใหม่ทุกครั้งที่ startup และเมื่อเรียก `POST /gold/refresh`

## 2.4 โครงสร้างเกณฑ์ชั่วโมง (ข้อมูลใน hourcategory / hoursubcategory)

| หมวด | ชม. | หมวดย่อย (ชม.) |
|---|---:|---|
| 1. พัฒนาทักษะชีวิต | 12 | กิจกรรมเสริมสร้างคุณค่าแห่งตน (8), กิจกรรมบูรณาการ 1 (4) |
| 2. TSU รับใช้สังคม | 12 | กิจกรรม TSU DO D : สร้างสรรค์สร้างสำนึกรับผิดชอบต่อสังคม (12) |
| 3. ศิลปวัฒนธรรมอาเซียน | 8 | กิจกรรมเรียนรู้ศิลปวัฒนธรรมอาเซียน (6), กิจกรรมบูรณาการ 3 (2) |
| 4. พัฒนาคุณธรรมและวินัย | 8 | กิจกรรมสร้างวินัยในตนเอง (4), กิจกรรมบูรณาการ 4 (4) |
| 5. ใฝ่เรียนรู้ตลอดชีวิต | 20 | ICT 1 (2), ICT 2 (2), รู้เท่าทันเทคโนโลยีดิจิทัล (4), ปฐมนิเทศ (4), ปัจฉิมนิเทศ (4), บูรณาการ 5 (4) |
| **รวม** | **60** | |

---

# 3. ข้อมูลสำหรับ CLASS DIAGRAM

## 3.1 Enumerations

```
«enum» UserRole        : student, staff, admin
«enum» StudentStatus   : active, inactive
«enum» EvidenceStatus  : pending, approved, rejected
«enum» ApprovalStatus  : pending, approved
«enum» OcrDecision     : auto_approved, needs_review, flagged
«enum» Intent          : HOURS, MISSING, OPEN_ACTIVITIES, REQUIRED,
                         RECOMMEND, RULES, GENERAL
```

## 3.2 Domain / Entity Classes (backend/app/models.py — SQLModel)

โครงสร้างจริงใช้ inheritance แบบ Base → Table/Create/Update/Read (แสดงเป็น generalization ได้)

```
«abstract» StudentBase
  + student_id: str      + full_name: str
  + faculty: str         + major: str
  + year_level: int      + status: StudentStatus
        △
        ├── Student «table»   { + id: int, + participations: List<Participation> }
        ├── StudentCreate «DTO»
        └── StudentRead   «DTO» { + id: int }
    StudentUpdate «DTO» (ทุกฟิลด์ optional)

«abstract» ActivityBase
  + name: str            + activity_type: str
  + is_required: bool    + max_participants: int
  + start_at: datetime   + location: str
  + hours: float         + subcategory_id: int?
        △
        ├── Activity «table» { + id, + created_by: int?, + approval_status,
        │                      + approved_by: int?, + approved_at: datetime?,
        │                      + participations: List<Participation> }
        ├── ActivityCreate «DTO» { subcategory_id required, hours > 0, max_participants > 0 }
        └── ActivityRead   «DTO» { + id, + participant_count: int }
    ActivityUpdate «DTO»

«abstract» ParticipationBase
  + student_id: int      + activity_id: int
  + check_in_time: datetime?
  + hours_earned: float  + evidence_status: EvidenceStatus
        △
        ├── Participation «table» { + id, + student: Student, + activity: Activity }
        └── ParticipationRead «DTO» { + id, + activity_name, + has_evidence,
                                      + evidence_uploaded_at, + has_ocr,
                                      + ocr_decision, + ocr_match_score, + ocr_confidence }
    ParticipationCreate «DTO» (extra="forbid" — กัน inject hours_earned)
    ParticipationUpdate «DTO» (แก้ได้แค่ check_in_time, evidence_status)

«abstract» UserBase
  + username: str  + role: UserRole  + student_id: int?
        △
        ├── User «table» { + id, + hashed_password: str }
        ├── UserCreate «DTO» { + password: str }
        └── UserRead   «DTO» { + id }
    UserUpdate «DTO»

HourCategory «table»    { + id, + name, + required_hours,
                          + subcategories: List<HourSubcategory> }
HourSubcategory «table» { + id, + category_id, + name, + required_hours,
                          + category: HourCategory }
RawFile «table»         { + id, + bucket, + object_key, + original_filename,
                          + content_type, + size_bytes, + checksum,
                          + source_system, + uploaded_by, + ingested_at,
                          + participation_id }
SilverEvidenceOcr «table» { + id, + raw_file_id, + participation_id,
                            + extracted_text, + ocr_confidence, + match_score,
                            + decision: OcrDecision, + is_duplicate, + processed_at }
```

## 3.3 Service / Infrastructure Classes (Strategy pattern ทั้ง 3 ชุด)

```
«interface» ObjectStorage                (app/storage.py)
  + ensure_bucket(bucket: str): void
  + upload_object(bucket, key, data: bytes, content_type: str): void
  + get_object_bytes(bucket, key): bytes
        △ implements
        ├── MinIOStorage      { - client: Minio }
        └── InMemoryStorage   { - _objects: Dict }

«interface» OcrEngine                    (app/ocr.py)
  + run_ocr(image_bytes: bytes): OcrResult   // OcrResult = (text: str, confidence: float)
        △
        ├── EasyOcrEngine  { - languages: List<str>, - _reader (lazy) }
        └── StubOcrEngine  { คืน ("", 0.0) }

«interface» LlmClient                    (app/llm.py)
  + embed(texts: List<str>): List<List<float>>
  + embed_query(text: str): List<float>
  + generate(prompt: str, system: str?): str
        △
        ├── GeminiClient { - api_key, - model, - embed_model }
        └── StubLlm      { - dim: int  // embedding จาก char n-gram แบบ deterministic }

«interface» VectorStore                  (app/vectorstore.py)
  + replace_source(source: str, chunks: List<StoredChunk>): void
  + search(embedding: List<float>, k: int): List<RetrievedChunk>
  + count(): int
        △
        ├── InMemoryVectorStore { - _chunks }
        └── PgVectorStore       { - engine, - dim }

StoredChunk    { + source, + chunk_index, + content, + embedding }
RetrievedChunk { + source, + chunk_index, + content, + score }
```

## 3.4 Application / Module Classes

```
«module» silver                          (app/silver.py) — Silver pipeline
  + process_participation_evidence(session, ocr, storage, participation_id): SilverEvidenceOcr?
  + process_evidence_in_background(participation_id): void
  + compute_match_score(text, student, activity): float
  - _latest_raw_file(session, participation_id): RawFile?
  - _is_duplicate(session, raw_file): bool
  - _extract_text(ocr, storage, raw_file): (str, float)
  - _fuzzy_hit / _best_partial_ratio / _name_tokens / _activity_score / _date_score
  const W_NAME=0.4, W_ACTIVITY=0.4, W_DATE=0.2, FUZZY_FLOOR=0.8

«module» gold                            (app/gold.py) — Gold layer builder
  + create_gold_layer(session): void      // DROP + CREATE ทุก view
  + init_gold_layer(engine): void
  - _view_definitions(dialect): List<(name, sql)>
  - _date_exprs(dialect, col): Dict       // รองรับทั้ง SQLite และ Postgres
  const GOLD_VIEW_NAMES: List<str>

«module» chatbot_sql                     (app/chatbot_sql.py)
  + classify_intent(question: str): Intent     // keyword-based, offline
  + answer_hours(session, student_id): ChatAnswer
  + answer_missing(session, student_id): ChatAnswer
  + answer_open_activities(session): ChatAnswer
  + answer_required_activities(session): ChatAnswer
  + recommend(session, student_id, question): ChatAnswer
  + run_text_to_sql(llm, session, question, student_id): ChatAnswer
  const TOTAL_REQUIRED_HOURS = 60, TTS_ALLOWED_TABLES, SCHEMA_PROMPT
ChatAnswer «dataclass» { + intent: Intent, + answer: str, + rows: List<Dict>, + needs_student: bool }

«module» sql_guard                       (app/sql_guard.py)
  + validate_select(sql: str, allowed_tables: Set<str>): str
  «exception» UnsafeSqlError
  // กติกา: 1 statement, ต้องเป็น SELECT, ห้าม comment, ตาราง/วิวต้องอยู่ใน allow-list

«module» rag                             (app/rag.py)
  + ingest_rules(llm, store, document): int
  + retrieve(llm, store, question, k): List<RetrievedChunk>
  + answer_rules_question(llm, store, question, k): (str, List<RetrievedChunk>)
  + chunk_document(text): List<str>
  const RULES_SOURCE, RULES_DOCUMENT

«module» auth                            (app/auth.py)
  + hash_password(password): str
  + verify_password(plain, hashed): bool
  + create_access_token(data: Dict, expires_delta?): str
  + get_current_user(token, session): User
  + require_roles(*roles): Callable
  + require_writer / require_admin

«singleton» Settings (BaseSettings)      (app/config.py)
  database_url, jwt_secret, jwt_algorithm, access_token_expire_minutes, cors_origins,
  storage_backend, minio_endpoint/root_user/root_password/secure/bucket_bronze,
  ocr_backend, ocr_languages, ocr_auto_confidence(0.6), ocr_auto_match(0.7),
  llm_backend, gemini_api_key, gemini_model, gemini_embed_model,
  vector_backend, rag_top_k(4)
```

## 3.5 Controller Classes (FastAPI Routers)

| Router | Prefix | Dependency ระดับ router | Operations |
|---|---|---|---|
| `AuthRouter` | `/auth` | – | login, register(admin), list_users, update_user, delete_user |
| `StudentsRouter` | `/students` | `get_current_user` | list, my_hours_summary, student_hours_summary, get, create(admin), update(admin), delete(admin) |
| `ActivitiesRouter` | `/activities` | `get_current_user` | list, get, create(writer), update(writer), approve(admin), list_participations(writer), delete(writer) |
| `ParticipationsRouter` | `/participations` | `get_current_user` | list, get, register_self(student), create(writer), update(writer), delete, upload_evidence, process_evidence, get_ocr_result, get_evidence |
| `HourCategoriesRouter` | `/hour-categories` | `get_current_user` | list |
| `GoldRouter` | `/gold` | – | refresh(admin) |
| `DashboardRouter` | `/dashboard` | `require_admin` | overview, by_category, at_risk, low_participation, by_faculty, trend |
| `ChatbotRouter` | `/chatbot` | – | ask(student only) |

**Response models ของ Dashboard** (ใช้เป็น class ในไดอะแกรมได้)
```
OverviewStats { total_students, passed_count, passed_percent, avg_hours,
                activity_count, required_hours_total }
CategoryStat  { category_key?, category_name, required_hours, avg_earned_hours }
AtRiskStudent { student_key, student_code, full_name, faculty, year_level,
                earned_hours, required_hours, percent, missing_hours }
LowParticipationActivity { activity_key, name, activity_type, max_participants,
                           participant_count, fill_percent }
FacultyStat   { faculty, year_level, total_students, passed_count, passed_percent }
TrendPoint    { period, year, month, count }
Page<T>       { items: List<T>, total: int, skip: int, limit: int }
Token         { access_token: str, token_type: str = "bearer" }
HourCategorySummary { id, name, required_hours, earned_hours, completed,
                      subcategories: List<HourSubcategorySummary> }
HourSubcategorySummary { id, name, required_hours, earned_hours, completed }
```

## 3.6 Frontend Classes (Flutter — ถ้าต้องวาด Class Diagram ฝั่ง client)

```
MyApp (StatelessWidget) → HomeScreen | LoginScreen  (สลับตาม authService.isLoggedIn)

«singleton» AuthService extends ChangeNotifier
  + token: String?  + username: String?  + role: String?
  + isLoggedIn: bool  + canWrite: bool  + isAdmin: bool
  + login(username, password): Future<void>
  + logout(): void
  - _decodeJwtPayload(jwt): Map

«static» ApiService
  + fetchPage<T>(path, fromJson, query): Future<Page<T>>
  + fetchAll<T>() / fetchList<T>() / fetchObject<T>()
  + create<T>() / update<T>() / delete() / patch<T>()
  + uploadEvidence(participationId, bytes, filename): Future<Participation>
  + processEvidence(participationId): Future<OcrResult>
  + fetchOcrResult(participationId): Future<OcrResult?>
  + fetchEvidence(participationId): Future<(Uint8List, String)>
  + askChatbot(question): Future<ChatResponse>

Models: Activity, AppUser, ChatResponse, Dashboard, HourCategory,
        HourSummary, OcrResult, Page<T>, Participation, Student

Screens: LoginScreen, HomeScreen, DashboardScreen, StudentsScreen,
         ActivitiesScreen, ActivityCalendarScreen, ActivityParticipantsScreen,
         ParticipationsScreen, RegisterActivitiesScreen, MyHoursScreen,
         StudentHoursScreen, OcrReviewScreen, UsersScreen, ChatbotScreen

Widgets: AppDataTable, AppFormDialog, EvidenceActions, EvidencePreview,
         HourSummaryView, KpiCard, PaginationBar, SearchField, StatusChip,
         SubcategoryDropdown, TypingIndicator, EmptyState
```

---

# 4. ข้อมูลสำหรับ SEQUENCE DIAGRAM

## SD-1: เข้าสู่ระบบ (Login)

**Participants:** Student/Staff/Admin, LoginScreen, AuthService, AuthRouter(`/auth/login`), Database

```
Actor → LoginScreen        : กรอก username + password
LoginScreen → AuthService  : login(username, password)
AuthService → AuthRouter   : POST /auth/login (form-urlencoded)
AuthRouter → Database      : SELECT * FROM user WHERE username = ?
Database --> AuthRouter    : User | null
alt ไม่พบ user หรือ verify_password() ล้มเหลว
    AuthRouter --> AuthService : 401 "Incorrect username or password"
    AuthService --> LoginScreen: throw Exception → แสดง error
else สำเร็จ
    AuthRouter → AuthRouter   : create_access_token({sub: username, role: role})
    AuthRouter --> AuthService: 200 { access_token, token_type: "bearer" }
    AuthService → AuthService : _decodeJwtPayload() → เก็บ token/username/role
    AuthService → MyApp       : notifyListeners()
    MyApp → HomeScreen        : แสดงเมนูตาม role
end
```

## SD-2: นิสิตสมัครกิจกรรมด้วยตนเอง

**Participants:** Student, RegisterActivitiesScreen, ApiService, ParticipationsRouter, Database

```
Student → RegisterActivitiesScreen : กดปุ่ม "สมัคร" (เห็นชั่วโมง/หมวดที่จะได้ก่อนกด)
Screen → ApiService                : create('/participations/register', {activity_id})
ApiService → ParticipationsRouter  : POST /participations/register + Bearer token
ParticipationsRouter → auth        : get_current_user(token)
auth → Database                    : SELECT user WHERE username = sub
auth --> ParticipationsRouter      : User

alt role != student                     → 403 Insufficient permissions
alt user.student_id == null             → 403 บัญชีไม่ได้ผูกกับข้อมูลนิสิต
ParticipationsRouter → Database    : SELECT activity WHERE id = ?
alt ไม่พบกิจกรรม                        → 400 activity_id does not exist
alt approval_status != approved         → 400 กิจกรรมนี้ยังไม่เปิดรับสมัคร
alt start_at <= now                     → 400 กิจกรรมนี้ปิดรับสมัครแล้ว
ParticipationsRouter → Database    : SELECT participation WHERE student & activity
alt สมัครไปแล้ว                          → 400 คุณสมัครกิจกรรมนี้ไปแล้ว
ParticipationsRouter → Database    : SELECT COUNT(*) participation WHERE activity_id
alt count >= max_participants           → 400 กิจกรรมนี้เต็มแล้ว
else ผ่านทุกเงื่อนไข
    ParticipationsRouter → Database: INSERT participation
                                     (evidence_status=pending, hours_earned=0)
    Database --> ParticipationsRouter : Participation
    ParticipationsRouter --> ApiService : 201 ParticipationRead
    ApiService --> Screen             : อัปเดตรายการ + SnackBar สำเร็จ
end
```

## SD-3: อัปโหลดหลักฐาน → Bronze → OCR Silver (**ไดอะแกรมสำคัญที่สุด**)

**Participants:** Student, ParticipationsScreen, ApiService, ParticipationsRouter, MinIO(ObjectStorage), Database, BackgroundTask, silver, OcrEngine

```
Student → ParticipationsScreen : เลือกไฟล์ใบประกาศ (JPEG/PNG/PDF)
Screen → ApiService            : uploadEvidence(participationId, bytes, filename)
ApiService → ParticipationsRouter : POST /participations/{id}/evidence (multipart)

ParticipationsRouter → Database : SELECT participation WHERE id
alt ไม่พบ                              → 404 Participation not found
alt role=student แต่ไม่ใช่ของตน         → 403
alt role=staff                         → 403 (staff อัปโหลดแทนไม่ได้)
alt evidence_status == approved        → 400 อนุมัติแล้ว อัปโหลดทับไม่ได้
alt content_type ไม่อยู่ใน allow-list    → 400 รองรับเฉพาะ JPEG/PNG/PDF
alt size > 10 MB                       → 413 ไฟล์ใหญ่เกิน 10 MB
alt size == 0                          → 400 ไฟล์ว่างเปล่า

ParticipationsRouter → ParticipationsRouter : data = file.read()
                                              checksum = SHA-256(data)
                                              object_key = evidence/year=.../month=.../
                                                 activity_id=A/participation_id=P/<uuid>_<name>
ParticipationsRouter → MinIO   : ensure_bucket("bronze")
ParticipationsRouter → MinIO   : upload_object(bucket, object_key, data, content_type)
                                 【BRONZE: เขียน object ใหม่เสมอ ไม่ทับของเดิม】
ParticipationsRouter → Database: INSERT raw_file (metadata + lineage)
ParticipationsRouter → Database: UPDATE participation SET evidence_status = 'pending'
ParticipationsRouter --> ApiService : 201 ParticipationRead  (ตอบกลับทันที ไม่รอ OCR)
ParticipationsRouter → BackgroundTask : add_task(silver.process_evidence_in_background, id)

== async: SILVER LAYER ==
BackgroundTask → silver        : process_evidence_in_background(participation_id)
silver → Database              : เปิด Session ใหม่ (session เดิมปิดไปแล้ว)
silver → Database              : _latest_raw_file() — SELECT raw_file ล่าสุดของ participation
alt ไม่มีไฟล์                          → return None
silver → Database              : SELECT participation, student, activity
silver → MinIO                 : get_object_bytes(bucket, object_key)
silver → OcrEngine             : run_ocr(image_bytes)      【AI: EasyOCR th+en】
OcrEngine --> silver           : (extracted_text, confidence)
silver → Database              : _is_duplicate() — SELECT raw_file WHERE checksum เดียวกัน
                                 และ participation นั้น approved แล้ว
silver → silver                : compute_match_score(text, student, activity)
                                 = 0.4×ชื่อนิสิต + 0.4×ชื่อกิจกรรม + 0.2×ปี (fuzzy ≥ 0.8)

alt is_duplicate == true
    silver → silver            : decision = flagged  (ไม่อนุมัติอัตโนมัติเด็ดขาด)
else evidence_status == pending
     AND confidence >= 0.6 AND match_score >= 0.7
    silver → silver            : decision = auto_approved
    silver → Database          : UPDATE participation
                                 SET evidence_status='approved',
                                     hours_earned = activity.hours   【ชั่วโมงมาจากกิจกรรม
                                                                       ไม่เคยมาจาก OCR】
else
    silver → silver            : decision = needs_review (รอเจ้าหน้าที่ตรวจ)
end
silver → Database              : INSERT silver_evidence_ocr
                                 (raw_file_id, participation_id, extracted_text,
                                  ocr_confidence, match_score, decision, is_duplicate)
note: ข้อผิดพลาดทั้งหมดถูกกลืน (log warning) — OCR ล้มเหลวต้องไม่ทำให้การอัปโหลดพัง
```

## SD-4: เจ้าหน้าที่ตรวจและอนุมัติหลักฐาน

**Participants:** Staff, OcrReviewScreen, ApiService, ParticipationsRouter, silver, Database, MinIO

```
Staff → OcrReviewScreen        : เปิดหน้าตรวจหลักฐาน
Screen → ApiService            : fetchOcrResult(participationId)
ApiService → ParticipationsRouter : GET /participations/{id}/ocr
ParticipationsRouter → Database   : SELECT silver_evidence_ocr ล่าสุด (ORDER BY id DESC)
ParticipationsRouter --> Screen   : SilverEvidenceOcrRead (text, confidence, match, decision)

Screen → ApiService            : fetchEvidence(participationId)      [ดูรูปใบประกาศ]
ApiService → ParticipationsRouter : GET /participations/{id}/evidence
ParticipationsRouter → ParticipationsRouter : ตรวจสิทธิ์ (นิสิตเจ้าของ / staff เจ้าของกิจกรรม / admin)
ParticipationsRouter → Database   : SELECT raw_file ล่าสุด
ParticipationsRouter → MinIO      : get_object_bytes()   【bucket ไม่เปิด public — backend เป็นตัวกลาง】
ParticipationsRouter --> Screen   : StreamingResponse (รูปภาพ/PDF)

opt Staff กด "ประมวลผลใหม่"
    Screen → ApiService            : processEvidence(participationId)
    ApiService → ParticipationsRouter : POST /participations/{id}/evidence/process
    alt role == student                 → 403 (นิสิตห้ามสั่งอนุมัติตัวเอง)
    alt role == staff แต่ไม่ใช่เจ้าของกิจกรรม → 403
    ParticipationsRouter → silver  : process_participation_evidence(...)   [ตาม SD-3]
    silver --> Screen              : SilverEvidenceOcrRead (ผลใหม่)
end

Staff → Screen                 : กด "อนุมัติ" / "ปฏิเสธ"
Screen → ApiService            : update('/participations/{id}', {evidence_status})
ApiService → ParticipationsRouter : PUT /participations/{id}
ParticipationsRouter → auth    : require_writer  (staff | admin)
ParticipationsRouter → Database: SELECT activity — ตรวจ staff เป็นเจ้าของกิจกรรมหรือไม่
alt evidence_status == approved
    ParticipationsRouter → Database : SELECT raw_file WHERE participation_id LIMIT 1
    alt ไม่มีหลักฐาน                 → 400 อนุมัติไม่ได้: ยังไม่มีหลักฐานการเข้าร่วม  【กฎ A3】
    ParticipationsRouter → ParticipationsRouter : hours_earned = activity.hours  【กฎ A2】
else pending / rejected
    ParticipationsRouter → ParticipationsRouter : hours_earned = 0               【กฎ E4】
end
ParticipationsRouter → Database: UPDATE participation
ParticipationsRouter --> Screen: 200 ParticipationRead
```

## SD-5: ผู้ดูแลระบบดูแดชบอร์ด (อ่านจาก Gold Layer)

**Participants:** Admin, DashboardScreen, ApiService, DashboardRouter, GoldViews(Database)

```
Admin → DashboardScreen        : เปิดหน้าแดชบอร์ด (เลือก faculty / year_level / semester)
par ยิงขนาน 6 endpoint
    Screen → DashboardRouter   : GET /dashboard/overview?faculty=&year_level=&semester=
    Screen → DashboardRouter   : GET /dashboard/by-category
    Screen → DashboardRouter   : GET /dashboard/at-risk
    Screen → DashboardRouter   : GET /dashboard/low-participation
    Screen → DashboardRouter   : GET /dashboard/by-faculty
    Screen → DashboardRouter   : GET /dashboard/trend
end
DashboardRouter → auth         : require_admin   【non-admin → 403 ทุก endpoint】
DashboardRouter → GoldViews    : SELECT SUM(required_hours) FROM gold_dim_hour_category
DashboardRouter → GoldViews    : SELECT student_key, SUM(hours_earned)
                                 FROM gold_fact_participation
                                 [JOIN gold_dim_date ON date_key WHERE semester = ?]
                                 GROUP BY student_key
DashboardRouter → GoldViews    : SELECT ... FROM gold_dim_student WHERE faculty/year_level
note: อ่านเฉพาะ gold_* views — ห้ามแตะตาราง operational โดยตรง
DashboardRouter --> Screen     : OverviewStats / List<CategoryStat> / List<AtRiskStudent> / ...
Screen → Admin                 : แสดง KPI card + กราฟ + ตารางกลุ่มเสี่ยง

opt Admin กด "รีเฟรช Gold Layer"
    Screen → GoldRouter        : POST /gold/refresh  (require_admin)
    GoldRouter → gold          : create_gold_layer(session)
    gold → Database            : DROP VIEW IF EXISTS ... ; CREATE VIEW ... (8 views)
    GoldRouter --> Screen      : { views: [...] }
end
```

## SD-6: นิสิตถามผู้ช่วยอัจฉริยะ (Chatbot — 3 เส้นทาง)

**Participants:** Student, ChatbotScreen, ApiService, ChatbotRouter, chatbot_sql, rag, LlmClient(Gemini), VectorStore, sql_guard, GoldViews

```
Student → ChatbotScreen        : พิมพ์คำถามภาษาไทย
Screen → ApiService            : askChatbot(question)
ApiService → ChatbotRouter     : POST /chatbot/ask { question }
ChatbotRouter → auth           : require_roles(student)   【staff/admin → 403】
alt question ว่าง                    → 400 กรุณาพิมพ์คำถาม
ChatbotRouter → chatbot_sql    : classify_intent(question)   【keyword-based, offline】
chatbot_sql --> ChatbotRouter  : Intent

alt Intent == RULES                                    ── เส้นทาง A: RAG ──
    ChatbotRouter → rag        : answer_rules_question(llm, store, question, k=4)
    rag → LlmClient            : embed_query(question)      【Gemini embedding】
    LlmClient --> rag          : embedding vector
    rag → VectorStore          : search(embedding, k=4)     【cosine / pgvector】
    VectorStore --> rag        : List<RetrievedChunk> (ท่อนจากเอกสารเกณฑ์ TSU)
    rag → rag                  : _build_prompt(question, chunks)
    rag → LlmClient            : generate(prompt)           【Gemini】
    LlmClient --> rag          : คำตอบภาษาไทยที่อ้างอิงเอกสาร
    rag --> ChatbotRouter      : (answer, chunks)
    ChatbotRouter --> Screen   : AskResponse { intent, answer, sources[] }

else Intent ∈ {OPEN_ACTIVITIES, REQUIRED}              ── เส้นทาง B: SQL สาธารณะ ──
    ChatbotRouter → chatbot_sql: answer_open_activities() / answer_required_activities()
    chatbot_sql → GoldViews    : SELECT ... FROM gold_activity_catalog
    chatbot_sql --> ChatbotRouter : ChatAnswer

else Intent ∈ {HOURS, MISSING, RECOMMEND}              ── เส้นทาง C: SQL ผูกกับนิสิต ──
    alt current_user.student_id == null → 400 บัญชียังไม่ผูกกับข้อมูลนิสิต
    ChatbotRouter → chatbot_sql: answer_hours/answer_missing/recommend(session, student_id)
    chatbot_sql → GoldViews    : SELECT ... FROM gold_student_hours
                                 WHERE student_key = :sid       【SQL ระบบเขียนเอง
                                                                  student_id เป็น bound param
                                                                  LLM ไม่เกี่ยวข้อง】
    chatbot_sql --> ChatbotRouter : ChatAnswer

else Intent == GENERAL                                 ── เส้นทาง D: Text-to-SQL ──
    ChatbotRouter → chatbot_sql: run_text_to_sql(llm, session, question, student_id)
    chatbot_sql → LlmClient    : generate(SCHEMA_PROMPT.format(question))
    LlmClient --> chatbot_sql  : SQL ที่ LLM แต่ง (ยังไม่เชื่อถือ)
    chatbot_sql → chatbot_sql  : _clean_sql() ตัด markdown fence
    chatbot_sql → sql_guard    : validate_select(sql, TTS_ALLOWED_TABLES)
    alt UnsafeSqlError  (มีหลาย statement / ไม่ใช่ SELECT / มี comment /
                          อ้างตารางนอก allow-list / มีคำสั่ง DML-DDL)
        sql_guard --> chatbot_sql : raise
        chatbot_sql --> ChatbotRouter : "ขออภัย ฉันไม่สามารถประมวลผลคำถามนี้ได้อย่างปลอดภัย"
    else ผ่าน
        chatbot_sql → chatbot_sql : ห่อ SQL ด้วย CTE
              WITH my_hours AS (SELECT * FROM gold_student_hours WHERE student_key = :sid)
              <SQL ของ LLM>
              【บังคับขอบเขตนิสิตเชิงโครงสร้าง — LLM เข้าถึง gold_student_hours ดิบไม่ได้เลย】
        chatbot_sql → GoldViews  : execute(wrapped_sql, {sid})
        GoldViews --> chatbot_sql: rows (ของนิสิตคนนี้เท่านั้น)
        chatbot_sql --> ChatbotRouter : ChatAnswer (สร้างข้อความจาก rows — ไม่ส่ง rows กลับให้ LLM)
    end
end
ChatbotRouter --> Screen       : AskResponse
Screen → Student               : แสดงคำตอบ + แหล่งอ้างอิง (ถ้าเป็น RAG)
```

## SD-7: เจ้าหน้าที่สร้างกิจกรรม → ผู้ดูแลระบบอนุมัติ

```
Staff → ActivitiesScreen       : กรอกฟอร์ม (ชื่อ ประเภท หมวดย่อย ชั่วโมง จำนวนรับ วันเวลา สถานที่)
Screen → ApiService            : create('/activities', payload)
ApiService → ActivitiesRouter  : POST /activities
ActivitiesRouter → auth        : require_writer (staff | admin)
ActivitiesRouter → validation  : ActivityCreate — subcategory_id บังคับ, hours > 0, max_participants > 0
alt role == admin
    ActivitiesRouter → ActivitiesRouter : approval_status = approved,
                                          approved_by = user.id, approved_at = now
else role == staff
    ActivitiesRouter → ActivitiesRouter : approval_status = pending
end
ActivitiesRouter → Database    : INSERT activity (created_by = user.id)
ActivitiesRouter --> Screen    : 201 ActivityRead

... (นิสิตยังไม่เห็นกิจกรรมนี้ เพราะกรองเฉพาะ approved) ...

Admin → ActivitiesScreen       : กด "อนุมัติ"
Screen → ActivitiesRouter      : PATCH /activities/{id}/approve
ActivitiesRouter → auth        : require_admin
ActivitiesRouter → Database    : UPDATE activity SET approval_status='approved',
                                 approved_by=admin.id, approved_at=now
ActivitiesRouter --> Screen    : 200 ActivityRead
note: ถ้า staff แก้กิจกรรมภายหลัง (PUT) สถานะจะกลับเป็น pending ต้องอนุมัติใหม่
```

## SD-8: ระบบเริ่มทำงาน (Application Startup — ถ้าต้องวาด)

```
Docker → backend               : alembic upgrade head
Docker → backend               : python seed.py
Docker → backend               : uvicorn app.main:app
uvicorn → main.lifespan        : startup
main → database                : create_db_and_tables()
main → gold                    : init_gold_layer(engine) → สร้าง 8 gold views ใหม่
alt ล้มเหลว → log warning (ไม่หยุดการบูต)
main → ObjectStorage           : ensure_bucket("bronze")
alt ล้มเหลว → log warning
main → rag                     : ingest_rules(llm, vector_store)
rag → LlmClient                : embed(chunks ของเอกสารเกณฑ์)
rag → VectorStore              : replace_source("tsu_activity_criteria", chunks)
alt ล้มเหลว → log warning
main → FastAPI                 : include_router × 8
```

---

# 5. กฎทางธุรกิจสำคัญ (Business Rules) — ใช้ตรวจความสมเหตุสมผลของทุกไดอะแกรม

| รหัส | กฎ |
|---|---|
| **A1** | นิสิตล็อกอินด้วยรหัสนิสิต 9 หลัก รหัสผ่านเริ่มต้น = รหัสนิสิต |
| **A2** | `hours_earned` มาจาก `activity.hours` เท่านั้น — ไม่มีใครพิมพ์เองได้ ทั้ง DTO `ParticipationCreate`/`ParticipationUpdate` ตั้ง `extra="forbid"` |
| **A3** | อนุมัติหลักฐานไม่ได้ถ้าไม่มีไฟล์ใน Bronze (`raw_file`) |
| **E4** | สถานะ pending / rejected → `hours_earned = 0` |
| **B1** | Bronze เป็น immutable — อัปโหลดใหม่สร้าง object ใหม่เสมอ ระบบใช้ไฟล์ล่าสุด |
| **B2** | bucket ไม่เปิด public — ดูไฟล์ต้องผ่าน backend ที่ตรวจสิทธิ์ |
| **S1** | ไฟล์ checksum ซ้ำกับหลักฐานที่ approved แล้ว → `flagged` ห้ามอนุมัติอัตโนมัติ |
| **S2** | auto-approve เมื่อ `ocr_confidence >= 0.6` **และ** `match_score >= 0.7` **และ** ยัง pending |
| **S3** | match_score = 0.4×ชื่อนิสิต + 0.4×ชื่อกิจกรรม + 0.2×ปี (พ.ศ./ค.ศ.) โดยใช้ fuzzy matching (floor 0.8) เพราะ OCR ภาษาไทยมักอ่านเพี้ยน |
| **G1** | Gold fact นับเฉพาะ participation ที่ `evidence_status = 'approved'` |
| **G2** | Dashboard และ Chatbot ห้ามอ่านตาราง operational — ต้องผ่าน `gold_*` views |
| **C1** | Chatbot ใช้ได้เฉพาะ role student และบัญชีต้องผูกกับข้อมูลนิสิต |
| **C2** | Text-to-SQL ต้องผ่าน `sql_guard.validate_select` และถูกครอบด้วย CTE `my_hours` ที่กรองด้วย student_id เสมอ |
| **C3** | เอกสารเกณฑ์เป็นข้อมูลสาธารณะ ส่งให้ LLM ได้ / ข้อมูลนิสิตห้ามออกจาก backend |
| **P1** | นิสิตสมัครกิจกรรมเดียวกันซ้ำไม่ได้ / กิจกรรมต้อง approved / ยังไม่ถึงวันจัด / ยังไม่เต็ม |
| **P2** | นิสิตยกเลิกการสมัครได้เฉพาะเมื่อยังไม่เช็กอินและยังไม่อนุมัติ |
| **F1** | Staff เห็น/แก้ได้เฉพาะกิจกรรมที่ตนสร้าง (row-level access) |
| **F2** | Staff แก้กิจกรรม → สถานะกลับเป็น pending ต้องให้ admin อนุมัติใหม่ |
| **F3** | Admin สร้างกิจกรรม → approved ทันที |
| **R1** | ครบเกณฑ์จบ = สะสมชั่วโมงที่อนุมัติแล้ว ≥ 60 ชม. ตาม 5 หมวด |
| **R2** | กลุ่มเสี่ยง (at-risk) = ได้ชั่วโมงต่ำกว่า 50% ของเกณฑ์ (< 30 ชม.) |

---

# 6. ตาราง API ครบทุก endpoint (อ้างอิงเวลาวาด Sequence)

| Method | Path | สิทธิ์ | คำอธิบาย |
|---|---|---|---|
| GET | `/health` | สาธารณะ | health check |
| POST | `/auth/login` | สาธารณะ | รับ JWT |
| POST | `/auth/register` | admin | สร้างผู้ใช้ |
| GET | `/auth/users` | admin | รายชื่อผู้ใช้ (paginate) |
| PUT | `/auth/users/{id}` | admin | แก้ role/รหัสผ่าน/ผูกนิสิต |
| DELETE | `/auth/users/{id}` | admin | ลบผู้ใช้ |
| GET | `/students` | ทุก role | รายชื่อนิสิต + ค้นหา |
| GET | `/students/me/hours-summary` | student | สรุปชั่วโมงตนเอง |
| GET | `/students/{id}/hours-summary` | ตามสิทธิ์แถว | สรุปชั่วโมงนิสิตคนหนึ่ง |
| GET | `/students/{id}` | ทุก role | รายละเอียดนิสิต |
| POST/PUT/DELETE | `/students[/{id}]` | admin | CRUD นิสิต |
| GET | `/activities` | ทุก role (กรองตาม role) | รายการกิจกรรม |
| GET | `/activities/{id}` | ทุก role | รายละเอียด |
| POST | `/activities` | staff/admin | สร้าง |
| PUT | `/activities/{id}` | staff(ของตน)/admin | แก้ไข |
| PATCH | `/activities/{id}/approve` | admin | อนุมัติกิจกรรม |
| GET | `/activities/{id}/participations` | staff(ของตน)/admin | รายชื่อผู้เข้าร่วม |
| DELETE | `/activities/{id}` | staff(ของตน)/admin | ลบ (ลบ participation ที่เกี่ยวข้องด้วย) |
| GET | `/participations` | ทุก role (กรองตาม role) | รายการ + ค้นหา |
| GET | `/participations/{id}` | ตามสิทธิ์แถว | รายละเอียด |
| POST | `/participations/register` | student | สมัครเอง |
| POST | `/participations` | staff/admin | บันทึกผู้เข้าร่วม |
| PUT | `/participations/{id}` | staff(ของตน)/admin | อนุมัติ/ปฏิเสธ/เช็กอิน |
| DELETE | `/participations/{id}` | student(ของตน มีเงื่อนไข)/staff/admin | ลบ |
| POST | `/participations/{id}/evidence` | student(ของตน)/admin | อัปโหลดหลักฐาน → Bronze |
| POST | `/participations/{id}/evidence/process` | staff(ของตน)/admin | รัน OCR ใหม่ → Silver |
| GET | `/participations/{id}/ocr` | ตามสิทธิ์แถว | ผล OCR ล่าสุด |
| GET | `/participations/{id}/evidence` | ตามสิทธิ์แถว | สตรีมไฟล์หลักฐาน |
| GET | `/hour-categories` | ทุก role | โครงสร้างหมวดชั่วโมง |
| POST | `/gold/refresh` | admin | สร้าง gold views ใหม่ |
| GET | `/dashboard/overview` | admin | KPI ภาพรวม |
| GET | `/dashboard/by-category` | admin | ชั่วโมงเฉลี่ยรายหมวด |
| GET | `/dashboard/at-risk` | admin | นิสิตกลุ่มเสี่ยง |
| GET | `/dashboard/low-participation` | admin | กิจกรรมที่คนสมัครน้อย |
| GET | `/dashboard/by-faculty` | admin | อัตราผ่านแยกคณะ/ชั้นปี |
| GET | `/dashboard/trend` | admin | แนวโน้มการเข้าร่วมตามเวลา |
| POST | `/chatbot/ask` | student | ถามผู้ช่วยอัจฉริยะ |

ทุก endpoint (ยกเว้น `/health` และ `/auth/login`) ต้องมี header `Authorization: Bearer <JWT>`

---

# 7. ข้อมูล Seed (ใช้อ้างอิงตัวเลขในไดอะแกรม/รายงาน)

- นิสิต **100 คน** — ชั้นปี 1–4 ปีละ 25 คน (รหัสขึ้นต้น 68/67/66/65), กระจาย 7 คณะ
- ผู้ใช้: `admin/admin123`, `staff/staff123`, และนิสิต 100 บัญชี (username = password = รหัสนิสิต)
- กิจกรรม **28 รายการ** (approved 25 / pending 3) กระจายครบทั้ง 5 หมวด
- การเข้าร่วม **> 1,100 แถว** กระจายให้เห็นครบทุกกลุ่ม: ผ่านเกณฑ์ / เกือบผ่าน / กลุ่มเสี่ยง (<50%) / ยังไม่เริ่ม
- ใบประกาศจริงสำหรับทดสอบ OCR **1,128 ใบ** (checksum ไม่ซ้ำกัน)
- หมวดชั่วโมง 5 หมวด / หมวดย่อย 13 รายการ / รวม 60 ชั่วโมง
