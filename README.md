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

- เปิดที่ `http://localhost:10052` (host port ของ console ที่ map ไป 9001 ในคอนเทนเนอร์) แล้ว login ด้วย `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` (ค่า default `minioadmin` / `minioadmin`)
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
**กิจกรรม → ปุ่ม QR "แสดง QR เช็กอิน"** เพื่อฉายที่หน้างาน

นิสิตเช็กอินได้ 3 ทาง ทุกทางไปจบที่ `POST /participations/checkin` เหมือนกัน:

| ทาง | ใช้เมื่อ |
|---|---|
| **สแกนด้วยกล้องมือถือปกติ** → เด้งเปิดเว็บ → กดยืนยัน | ทางหลัก ไม่ต้องเปิดแอปก่อน |
| หน้าหลัก → "เช็กอินหน้างาน" → สแกนในแอป | มีแอปเปิดอยู่แล้ว |
| กรอกรหัสกิจกรรมที่แสดงใต้ QR | กล้องใช้ไม่ได้ |

QR เก็บ **URL เต็ม** (`{PUBLIC_APP_BASE_URL}/#/checkin?c=<token>`) กล้องมือถือจึงขึ้นปุ่ม
"เปิดลิงก์" ให้ ถ้ายังไม่ได้ล็อกอิน ระบบพาไปหน้า login ก่อนแล้วกลับมาหน้ายืนยันให้เอง
โดย token ไม่หาย · เปิดลิงก์ด้วยบัญชีเจ้าหน้าที่จะได้ข้อความ "บัญชีนี้เช็กอินไม่ได้
(เฉพาะนิสิต)" · **มีขั้นยืนยันเสมอ ไม่เช็กอินให้อัตโนมัติ**

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
cd backend && uvicorn app.main:app --reload            # เทอร์มินัลที่ 1
cd frontend && flutter run -d chrome --web-port=8080   # เทอร์มินัลที่ 2

# ถ้ากิจกรรมเดโมหมดช่วงเช็กอินแล้ว (seed ไว้ตั้งแต่เมื่อวาน) ให้เลื่อนเวลาใหม่:
cd backend && python seed.py --refresh-live
```

> **ต้องล็อกพอร์ตให้ตรงกับ `PUBLIC_APP_BASE_URL`** (ดีฟอลต์ `http://localhost:8080`)
> ไม่งั้นลิงก์ใน QR จะชี้ไปคนละพอร์ตกับที่แอปรันอยู่ — `flutter run -d chrome`
> เฉย ๆ จะสุ่มพอร์ตให้ทุกครั้ง

1. หน้าต่างที่ 1 ล็อกอิน `staff / staff123` → กิจกรรม → หา
   *"จิตอาสาพัฒนามหาวิทยาลัย (กำลังจัดอยู่ตอนนี้)"* → ปุ่ม QR
2. ถ่ายรูป QR นั้นด้วยมือถือ (หรือส่งภาพไปเปิดบนมือถือ)
3. เปิดหน้าต่างใหม่ที่ `localhost` เดิม ล็อกอินด้วยรหัสนิสิต (username = password = รหัสนิสิต)
   → หน้าหลัก → "เช็กอินหน้างาน" → "เปิดกล้องสแกน QR" → อนุญาตกล้อง
4. ยกมือถือที่มีภาพ QR ให้กล้องเว็บแคมส่อง → ขึ้นการ์ดเขียว "เช็กอินสำเร็จ"

อยากให้มือถือสแกนจอคอมโดยตรง ต้องเสิร์ฟแอปผ่าน HTTPS (เช่นทำ tunnel) หรือใส่ origin
ของเครื่องไว้ใน `chrome://flags/#unsafely-treat-insecure-origin-as-secure` บน Chrome
ของมือถือ

### ทดสอบ deep link (สแกนด้วยกล้องปกติ) โดยไม่ต้องมีมือถือ

เปิดลิงก์ตรง ๆ ในเบราว์เซอร์ก็เหมือนกับที่กล้องมือถือทำให้ทุกอย่าง:

```
http://localhost:8080/#/checkin?c=<token ที่แสดงใต้ QR>
```

- ยังไม่ล็อกอิน → หน้า login พร้อมแบนเนอร์บอกเหตุผล → ล็อกอินนิสิต → เด้งมาหน้ายืนยันเอง
- ล็อกอินนิสิตอยู่แล้ว → หน้า "ยืนยันเช็กอินกิจกรรมนี้?" → กดยืนยัน → การ์ดเขียว
- ล็อกอิน staff/admin → "บัญชีนี้เช็กอินไม่ได้ (เฉพาะนิสิต)"

**ตอน deploy จริงต้องตั้ง `PUBLIC_APP_BASE_URL` เป็นโดเมนจริง + HTTPS** ไม่งั้น QR จะ
ชี้ไป `localhost` ซึ่งในมือถือหมายถึงตัวเครื่องมือถือเอง เปิดไม่ถึงเซิร์ฟเวอร์

## ส่งออกรายงานชั่วโมง (Excel / PDF)

ปุ่ม **"ส่งออก Excel" / "ส่งออก PDF"** อยู่บนหน้าแดชบอร์ดผู้บริหาร (ใต้แถบตัวกรอง)
หรือเรียก API ตรง ๆ ได้ — **staff และ admin เท่านั้น**

```bash
curl -OJ -H "Authorization: Bearer <token>" \
  "http://localhost:8000/reports/student-hours.xlsx?faculty=วิทยาศาสตร์&year_level=4"
curl -OJ -H "Authorization: Bearer <token>" "http://localhost:8000/reports/student-hours.pdf"
```

- หนึ่งแถว = นิสิตหนึ่งคน × หมวดชั่วโมงหนึ่งหมวด (grain เดียวกับ `gold_student_hours`)
  คอลัมน์: รหัสนิสิต · ชื่อ-สกุล · คณะ · ชั้นปี · หมวดกิจกรรม · ชั่วโมงที่ได้ · ชั่วโมงที่ต้องการ · สถานะ
- กรองได้ตาม `faculty` / `year_level` — **ไม่มีตัวกรองภาคเรียน** เพราะรายงานเป็นยอด
  สะสมทั้งหลักสูตร (ต่างจากตัวเลขบนแดชบอร์ดที่กรองภาคเรียนได้)
- **PDF ต้องมีฟอนต์ไทยในเครื่องที่รัน backend** — docker ติดตั้ง `fonts-thai-tlwg` ให้แล้ว
  ถ้าไม่มีฟอนต์ endpoint จะตอบ 503 พร้อมข้อความบอกวิธีแก้ แทนการปล่อยไฟล์ที่ตัวอักษร
  เป็นกล่องสี่เหลี่ยมออกไป (Excel ไม่มีปัญหานี้ เพราะใช้ฟอนต์ของเครื่องที่เปิดไฟล์)

## นำเข้าแผนกิจกรรมทั้งภาคเรียน (Excel / CSV)

ปุ่ม **"นำเข้าแผนกิจกรรม"** อยู่มุมขวาบนของหน้าจัดการกิจกรรม — **staff และ admin เท่านั้น**

```bash
# ไฟล์ต้นแบบเปล่า (มีชีต "หมวดย่อยที่ใช้ได้" สร้างสดจากฐานข้อมูลแนบมาด้วย)
curl -OJ -H "Authorization: Bearer <token>" "http://localhost:8000/activities/import/template.xlsx"

# อัปโหลดแผนที่กรอกแล้ว
curl -X POST "http://localhost:8000/activities/import" \
  -H "Authorization: Bearer <token>" -F "file=@plan.xlsx"
```

- คอลัมน์: `ชื่อ` · `ประเภท` · `หมวดย่อย` · `วันเวลา` · `ชั่วโมง` · `สถานที่` · `จำนวนรับ` · `บังคับ`
  (คอลัมน์ `บังคับ` เว้นว่างได้ = ไม่บังคับ, บรรทัดชื่อเรื่องเหนือหัวตารางมีได้)
- **แถวเดียวผิดไม่ล้มทั้งไฟล์** — แถวที่ผ่านถูกสร้างจริง แถวที่ผิดถูกรายงานกลับพร้อม
  เลขแถวจริงในไฟล์และเหตุผล (วันย้อนหลัง / ไม่พบหมวดย่อย / ชั่วโมง ≤ 0 ฯลฯ)
- ช่อง `หมวดย่อย` กรอกได้ 3 แบบ: ชื่อหมวดย่อย, ชื่อเต็ม `หมวดแม่ › หมวดย่อย`
  (ใช้ `>` หรือ `/` คั่นก็ได้) หรือเลข id — ชื่อที่ซ้ำข้ามหมวดจะถูกขอให้ระบุชื่อเต็ม
- รับ **ปี พ.ศ.** ในช่องวันเวลาด้วย (2569 → 2026) และ CSV ที่ Excel ไทยบันทึกเป็น cp874
- สถานะอนุมัติใช้กฎเดียวกับการสร้างทีละอัน: **staff นำเข้า → รออนุมัติ, admin นำเข้า → อนุมัติแล้ว**
- กันอัปโหลดไฟล์เดิมซ้ำ: แถวที่ชื่อ+วันเวลาตรงกับกิจกรรมที่มีอยู่แล้ว (หรือซ้ำกันเองในไฟล์)
  ถูกปฏิเสธ · เพดาน 500 แถว / 5 MB ต่อครั้ง

## อีเมลแจ้งเตือนอัตโนมัติ

ส่งได้ 2 แบบ ทั้งคู่เป็น **admin เท่านั้น**

```bash
# 1) เตือนนิสิตที่ชั่วโมงยังไม่ถึงเกณฑ์ (อ่านจาก gold_student_hours)
curl -X POST "http://localhost:8000/notifications/at-risk" -H "Authorization: Bearer <admin-token>"
# กรองเฉพาะกลุ่มที่ใกล้จบ / เกณฑ์ % เองก็ได้
curl -X POST "http://localhost:8000/notifications/at-risk?year_level=4&threshold=80" -H "Authorization: Bearer <admin-token>"

# 2) ประชาสัมพันธ์กิจกรรมที่เปิดรับสมัคร ถึงนิสิตที่ยังไม่ได้สมัคร
curl -X POST "http://localhost:8000/notifications/activity/12" -H "Authorization: Bearer <admin-token>"
```

- ค่าเริ่มต้น `EMAIL_BACKEND=stub` คือ **ไม่ส่งจริง** (เก็บไว้ในหน่วยความจำ + เขียน log)
  ต้องตั้ง `EMAIL_BACKEND=smtp` พร้อม `SMTP_HOST/PORT/USER/PASSWORD/FROM` ใน `.env` เองเมื่อพร้อมส่ง
- ที่อยู่อีเมลนิสิตมาจากคอลัมน์ `student.email` ที่ผู้ดูแลกรอกเอง (**ไม่บังคับ** และระบบ
  ไม่เดาจากรหัสนิสิตให้) — ฟอร์มนิสิตมีปุ่มเติม `{รหัสนิสิต}@tsu.ac.th` ให้กดเองได้
  คนที่ยังไม่ระบุอีเมลจะถูก **ข้าม** ตอนส่ง และผลลัพธ์จะรายงานจำนวนที่ข้ามไว้ใน `skipped`
- รอบอัตโนมัติวันละครั้งปิดไว้ ต้อง `pip install APScheduler` แล้วตั้ง
  `NOTIFY_SCHEDULER_ENABLED=true` (+ `NOTIFY_AT_RISK_HOUR`, `NOTIFY_ACTIVITY_REMINDER_HOUR`)
  — **เปิดเมื่อรัน uvicorn worker เดียวเท่านั้น** ไม่งั้นอีเมลจะถูกส่งซ้ำตามจำนวน worker
- แจ้งเตือน **"พรุ่งนี้มีกิจกรรม"** ส่งล่วงหน้า 1 วันถึงคนที่สมัครไว้ (กิจกรรมที่อนุมัติแล้ว
  ไม่ถูกซ่อน และ `start_at` ตรงกับวันพรุ่งนี้ตามเวลาไทย) · สั่งเองได้ที่
  `POST /notifications/activity-reminders` และลอง `?dry_run=true` ดูรายชื่อผู้รับก่อนส่งจริง

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
