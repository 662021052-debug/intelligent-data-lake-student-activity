# สเปกงานสำหรับ Claude Code — ระบบ CRUD (เฟสเดือน ก.ค.)

> วิธีใช้: เปิดโฟลเดอร์โปรเจกต์เปล่าในเทอร์มินัล แล้วรัน `claude` จากนั้นวางเนื้อหาไฟล์นี้ทั้งหมดเป็นคำสั่งแรก
> เป้าหมายเฟสนี้: ทำ **CRUD ให้ครบและรันได้จริง** ภายในเดือนกรกฎาคม ยังไม่ทำ AI / Medallion / OCR / Dashboard

---

## 1. ภาพรวมโปรเจกต์

ส่วนหนึ่งของโครงงาน "Intelligent Data Lake for Student Activity Participation Tracking"
เฟสนี้ทำเฉพาะระบบหลังบ้าน + หน้าเว็บ CRUD สำหรับจัดการข้อมูล 3 ก้อน โดยใช้ **ข้อมูลสมมุติ**

## 2. Tech stack (ล็อกแล้ว)

- Backend: **Python + FastAPI + SQLModel**
- Database: **PostgreSQL** (dev ใช้ SQLite ได้เพื่อความเร็ว)
- Frontend: **Flutter Web** (responsive ใช้ได้ทุกอุปกรณ์)
- Auth: **JWT** + role (student / staff / admin), hash รหัสผ่านด้วย passlib (bcrypt)
- Deploy: **Docker Compose** (Postgres + FastAPI)

## 3. โครงสร้างข้อมูล (3 entity หลัก + user)

### student
- id (PK)
- student_id (รหัสนิสิต, unique)
- full_name
- faculty (คณะ)
- major (สาขา)
- year_level (ชั้นปี)
- status (กำลังศึกษา/พ้นสภาพ)

### activity
- id (PK)
- name (ชื่อกิจกรรม)
- activity_type (ประเภท)
- hour_category (หมวดชั่วโมง)
- is_required (บังคับ y/n)
- max_participants (จำนวนที่รับ)
- start_at, location

### participation (ตารางเชื่อม student × activity)
- id (PK)
- student_id (FK → student)
- activity_id (FK → activity)
- check_in_time
- hours_earned
- evidence_status (pending/approved/rejected)

### user (สำหรับ login)
- id (PK)
- username (unique)
- hashed_password
- role (student / staff / admin)

## 4. Backend — สิ่งที่ต้องมี

- โครงสร้าง `backend/app/` แยก `models.py`, `database.py`, `auth.py`, และ `routers/` ต่อ entity
- REST endpoint แบบ CRUD ครบทั้ง 3 entity:
  - `GET /students` (list + filter/pagination), `GET /students/{id}`, `POST /students`, `PUT /students/{id}`, `DELETE /students/{id}`
  - เหมือนกันสำหรับ `/activities` และ `/participations`
- Auth:
  - `POST /auth/login` → คืน JWT
  - `POST /auth/register` (เฉพาะ admin สร้าง user ได้)
  - endpoint ที่เขียนข้อมูล (POST/PUT/DELETE) ต้องมี JWT; role `student` อ่านได้อย่างเดียว, `staff`/`admin` แก้ได้
- ใช้ SQLModel ทำ model + schema ในตัวเดียว, validation ด้วย Pydantic
- เปิด CORS ให้ Flutter Web เรียกได้
- Swagger อัตโนมัติที่ `/docs`

## 5. Frontend (Flutter Web) — สิ่งที่ต้องมี

- หน้า **Login** → เก็บ JWT (in-memory / secure storage) แล้วแนบ header ทุกคำขอ
- หน้า **Home** มีเมนูไป 3 หน้าจัดการ
- แต่ละ entity มีหน้าจอ: ตารางรายการ + ปุ่มเพิ่ม/แก้/ลบ + ฟอร์ม (dialog หรือหน้าใหม่)
- Responsive: ใช้ `LayoutBuilder`/`Wrap` ให้ดูดีทั้งมือถือและจอใหญ่
- แยก `services/api_service.dart` (เรียก REST) และ `services/auth_service.dart`
- base URL ของ API อ่านจากตัวแปรตั้งค่าเดียว (แก้ง่ายตอน deploy)

## 6. Docker + รันงาน

- `docker-compose.yml`: service `db` (postgres:16) + `backend` (FastAPI)
- `backend/Dockerfile`
- ไฟล์ `.env.example` สำหรับ DB URL, JWT secret
- สคริปต์ `seed.py` ใส่ข้อมูลสมมุติ: user 3 role, นิสิต ~20 คน, กิจกรรม ~10 รายการ, การเข้าร่วม ~50 แถว
- `README.md` บอกวิธีรัน backend (docker compose up) และ frontend (flutter run -d chrome)

## 7. เกณฑ์ว่างานเสร็จ (acceptance)

- [ ] `docker compose up` แล้ว backend + Postgres ขึ้น, เข้า `/docs` ได้
- [ ] login ด้วย user ที่ seed แล้วได้ JWT
- [ ] เพิ่ม/อ่าน/แก้/ลบ ได้ครบทั้ง 3 entity ผ่าน Swagger
- [ ] Flutter Web login แล้วทำ CRUD ได้ครบ และ responsive บนจอเล็ก/ใหญ่
- [ ] มีเทสต์ backend อย่างน้อยชุด CRUD + auth (pytest) และผ่านทั้งหมด

## 8. ลำดับการทำที่แนะนำ (ให้ Claude Code ทำทีละเฟส)

1. ตั้งโครง backend + โมเดล + เชื่อม DB + seed
2. เขียน CRUD endpoint 3 entity + ทดสอบผ่าน Swagger/pytest
3. เพิ่ม JWT auth + role guard
4. ทำ docker-compose ให้รันครบ
5. สร้าง Flutter Web: login → api_service → 3 หน้าจอ CRUD
6. ทดสอบ end-to-end + เขียน README

> เริ่มจากข้อ 1 ก่อน แล้วให้หยุดรายงานความคืบหน้าเป็นเฟส ๆ เพื่อให้ฉันตรวจก่อนไปเฟสถัดไป
