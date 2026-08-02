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

ข้อมูลเดโมที่ `seed.py` สร้าง (ค่าคงที่ทุกครั้งเพราะตั้ง `RANDOM_SEED` ไว้): นิสิต **100 คน** ชั้นปี 1–4 ปีละ 25 คน (รหัสขึ้นต้น 68/67/66/65) กระจาย 7 คณะ, กิจกรรม 28 รายการ (อนุมัติแล้ว 25 / รออนุมัติ 3), การเข้าร่วมกว่า 1,100 แถว ชั่วโมงสะสมถูกกระจายให้เห็นครบทุกกลุ่มในแดชบอร์ด — ผ่านเกณฑ์ / เกือบผ่าน / กลุ่มเสี่ยง (<50%) / ยังไม่เริ่ม — ในทุกชั้นปี โดยปีสูงส่วนใหญ่ใกล้ครบ 60 ชม. และปี 1 เพิ่งเริ่มเก็บ

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

## เช็กอินหน้างานด้วย QR

แต่ละกิจกรรมมี `checkin_token` ประจำตัว เจ้าหน้าที่เจ้าของกิจกรรม (หรือ admin) เปิด
**กิจกรรม → ปุ่ม QR "แสดง QR เช็กอิน"** เพื่อฉายที่หน้างาน นิสิตเปิด **หน้าหลัก →
"เช็กอินหน้างาน"** แล้วสแกน ระบบบันทึก `check_in_time` ทันที

- เช็กอิน = บันทึกว่า "มาร่วมงาน" เท่านั้น **ไม่ให้ชั่วโมง** — ชั่วโมงยังต้องส่งหลักฐาน
  แล้วเจ้าหน้าที่อนุมัติตามกฎเดิม
- สแกนได้เฉพาะช่วง `start_at − CHECKIN_OPEN_BEFORE_MINUTES` ถึง
  `start_at + ชั่วโมงกิจกรรม + CHECKIN_CLOSE_AFTER_MINUTES` (ดีฟอลต์ 60 / 180 นาที)
- ตัวตนผู้เช็กอินมาจาก JWT เท่านั้น ส่ง token ให้เพื่อนสแกนแทนไม่ได้

### ข้อจำกัดเรื่องกล้องบนเว็บ

เบราว์เซอร์เปิดกล้องให้เฉพาะหน้าเว็บที่มาจาก **HTTPS** หรือ **localhost** เท่านั้น
เปิดแอปผ่าน IP ในวง LAN (เช่น `http://192.168.1.10:8080`) กล้องจะไม่ทำงาน — บนเซิร์ฟเวอร์
มหาวิทยาลัยจึงต้องมี HTTPS ทุกกรณี แอปมีทางเลือก **"กรอกรหัสกิจกรรม"** ไว้ให้เสมอ
โดยรหัสแสดงอยู่ใต้ QR บนจอของเจ้าหน้าที่

### ทดสอบกล้องจริงบนเครื่องเดียว

```bash
cd backend && uvicorn app.main:app --reload      # เทอร์มินัลที่ 1
cd frontend && flutter run -d chrome             # เทอร์มินัลที่ 2 (ได้ localhost → กล้องใช้ได้)

# ถ้ากิจกรรมเดโมหมดช่วงเช็กอินแล้ว (seed ไว้ตั้งแต่เมื่อวาน) ให้เลื่อนเวลาใหม่:
cd backend && python seed.py --refresh-live
```

1. หน้าต่างที่ 1 ล็อกอิน `staff / staff123` → กิจกรรม → หา
   *"จิตอาสาพัฒนามหาวิทยาลัย (กำลังจัดอยู่ตอนนี้)"* → ปุ่ม QR
2. ถ่ายรูป QR นั้นด้วยมือถือ (หรือส่งภาพไปเปิดบนมือถือ)
3. เปิดหน้าต่างใหม่ที่ `localhost` เดิม ล็อกอินด้วยรหัสนิสิต (username = password = รหัสนิสิต)
   → หน้าหลัก → "เช็กอินหน้างาน" → "เปิดกล้องสแกน QR" → อนุญาตกล้อง
4. ยกมือถือที่มีภาพ QR ให้กล้องเว็บแคมส่อง → ขึ้นการ์ดเขียว "เช็กอินสำเร็จ"

อยากให้มือถือสแกนจอคอมโดยตรง ต้องเสิร์ฟแอปผ่าน HTTPS (เช่นทำ tunnel) หรือใส่ origin
ของเครื่องไว้ใน `chrome://flags/#unsafely-treat-insecure-origin-as-secure` บน Chrome
ของมือถือ

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
