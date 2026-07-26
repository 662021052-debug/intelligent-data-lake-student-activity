# Intelligent Data Lake for Student Activity Participation Tracking

ระบบ CRUD จัดการข้อมูลนิสิต / กิจกรรม / การเข้าร่วมกิจกรรม (เฟส ก.ค. — ยังไม่รวม AI / Medallion / OCR / Dashboard)

## Tech stack

- Backend: Python + FastAPI + SQLModel
- Database: PostgreSQL (dev ใช้ SQLite ได้)
- Object storage (Bronze layer): MinIO (S3-compatible) เก็บไฟล์หลักฐานดิบ
- Frontend: Flutter Web
- Auth: JWT + role (student / staff / admin)
- Deploy: Docker Compose (Postgres + FastAPI + MinIO)

## รัน Backend ด้วย Docker Compose (แนะนำ)

```bash
docker compose up --build
```

- Postgres จะขึ้นที่ port `5432`, backend ที่ `http://localhost:8000`, MinIO ที่ `9000` (API) / `9001` (Console)
- คอนเทนเนอร์ backend จะรัน `seed.py` อัตโนมัติก่อนเปิดเซิร์ฟเวอร์ (รันซ้ำได้ ข้อมูลจะไม่ซ้ำ) และสร้าง bucket `bronze` ให้อัตโนมัติตอน startup
- เปิด Swagger ได้ที่ `http://localhost:8000/docs`
- ปรับค่า `JWT_SECRET` ฯลฯ ได้ผ่าน environment variable หรือสร้างไฟล์ `.env` จาก `.env.example` ที่ root แล้ว docker compose จะอ่านมาแทนค่า default อัตโนมัติ

### MinIO Console (Bronze layer)

- เปิดที่ `http://localhost:9001` แล้ว login ด้วย `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` (ค่า default `minioadmin` / `minioadmin`)
- ไฟล์หลักฐานที่นิสิตอัปโหลดจะเก็บใน bucket `bronze` ภายใต้ path
  `evidence/year=<YYYY>/month=<MM>/activity_id=<A>/participation_id=<P>/<uuid>_<ชื่อไฟล์เดิม>`
- Bronze = ชั้นข้อมูลดิบ **immutable**: อัปโหลดใหม่จะเก็บเป็น object ใหม่เสมอ ไม่ทับของเดิม และทุกไฟล์มี metadata ครบ (timestamp + source) ในตาราง `raw_file` (data lineage)
- bucket ไม่เปิด public — การดูไฟล์ต้องผ่าน backend ที่ตรวจสิทธิ์ก่อน (`GET /participations/{id}/evidence`)
- รัน backend แบบ local โดยไม่มี MinIO ได้ด้วยการตั้ง `STORAGE_BACKEND=memory` (เก็บไฟล์ในหน่วยความจำ ไม่คงอยู่หลัง restart — สำหรับ dev/test เท่านั้น)

หยุดและลบคอนเทนเนอร์:

```bash
docker compose down          # เก็บข้อมูลใน volume ไว้
docker compose down -v       # ลบข้อมูลใน Postgres ด้วย
```

## รัน Backend แบบ local (dev เร็ว ใช้ SQLite)

```bash
cd backend
python -m venv .venv
source .venv/Scripts/activate   # Windows Git Bash; หรือ .venv\Scripts\Activate.ps1 บน PowerShell
pip install -r requirements-dev.txt
python seed.py
uvicorn app.main:app --reload
```

ค่าเริ่มต้นใช้ SQLite (`backend/dev.db`) ไม่ต้องตั้งค่าอะไรเพิ่ม

รันเทส:

```bash
cd backend
pytest
```

## Database migrations (Alembic)

Schema เปลี่ยน (เพิ่ม/แก้ไข column, table) ให้ใช้ Alembic แทนการลบ `dev.db` ทิ้ง — `SQLModel.metadata.create_all()` (ที่รันตอน startup และใน `seed.py`) สร้างเฉพาะตารางที่ยังไม่มี ไม่ migrate ตารางที่มีอยู่แล้ว

```bash
cd backend

# หลังแก้ backend/app/models.py แล้ว สร้าง migration ใหม่จาก diff อัตโนมัติ
alembic revision --autogenerate -m "อธิบายการเปลี่ยนแปลง"

# ตรวจสอบไฟล์ที่ alembic/versions/ ที่ generate ก่อนรัน แล้วค่อย apply
alembic upgrade head

# ย้อนกลับ 1 migration ถ้าจำเป็น
alembic downgrade -1
```

Alembic อ่าน connection URL จาก `app.config.settings.database_url` เดียวกับแอป (ผ่าน env var `DATABASE_URL` หรือ `.env`) ไม่ต้องแก้ `alembic.ini`

**ข้อควรระวัง**: SQLModel autogenerate มักไม่ import `sqlmodel` ให้เองในไฟล์ migration ที่ generate ใหม่ (มี `import sqlmodel` เพิ่มไว้ใน `alembic/script.py.mako` แล้วเพื่อแก้ปัญหานี้ล่วงหน้า) — ถ้าเจอ `NameError: name 'sqlmodel' is not defined` ตอนรัน `alembic upgrade`, ให้เช็คว่าไฟล์ migration มี `import sqlmodel` อยู่บนสุดหรือไม่

## ผู้ใช้ที่ seed ไว้ (สำหรับทดสอบ login)

| username | password    | role    |
|----------|-------------|---------|
| admin    | admin123    | admin   |
| staff    | staff123    | staff   |
| *รหัสนิสิต* | *รหัสนิสิต* | student |

นิสิตจะ **ล็อกอินด้วยรหัสนิสิต** (รหัส 9 หลักแบบ ม.ทักษิณ เช่น `662021052`) โดยรหัสผ่านเริ่มต้น = รหัสนิสิต — ไม่มีบัญชีชื่อ `student` อีกต่อไป สคริปต์ `seed.py` จะพิมพ์ตัวอย่างรหัสนิสิตของนิสิตเดโมออกมาให้ตอนรัน

`role: student` อ่านข้อมูลได้อย่างเดียว, `staff`/`admin` แก้ไขข้อมูลได้ (POST/PUT/DELETE), `admin` เท่านั้นที่สร้าง user ใหม่ได้ผ่าน `POST /auth/register`

## Frontend (Flutter Web)

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

- ค่าเริ่มต้นแอปจะเรียก backend ที่ `http://localhost:8000` (ตั้งค่าใน `lib/config.dart`)
- ถ้า backend รันอยู่คนละ URL ให้สั่ง `flutter run -d chrome --dart-define=API_BASE_URL=https://your-api.example.com`
- Login ด้วย user ที่ seed ไว้ (ตารางด้านบน) แล้วใช้งานเมนู นิสิต / กิจกรรม / การเข้าร่วมกิจกรรม ได้ทันที
- รันเทส widget:

```bash
cd frontend
flutter test
```

Build สำหรับ deploy จริง:

```bash
cd frontend
flutter build web
```

## โครงสร้างโปรเจกต์

```
backend/
  app/
    models.py       # SQLModel: Student, Activity, Participation, User
    database.py     # engine + session
    auth.py          # JWT + password hashing + role guard
    config.py        # อ่าน env
    routers/         # students, activities, participations, auth
  seed.py            # ใส่ข้อมูลสมมุติ
  tests/             # pytest (CRUD + auth)
  Dockerfile
docker-compose.yml
.env.example
```
