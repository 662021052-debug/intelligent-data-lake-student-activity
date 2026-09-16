# Checklist อัปขึ้นเซิร์ฟเวอร์ (single port 5052)

เซิร์ฟเวอร์: `ssh s662021052@miscis.scidi.tsu.ac.th` · path `/var/www/662021052` ·
URL `http://miscis.scidi.tsu.ac.th:5052/` · เปิดออกนอกได้พอร์ตเดียว (5052)

> **Dry-run ครบทุกข้อเมื่อ 2026-09-16** บนเครื่อง dev: clone จาก GitHub ลงโฟลเดอร์ `app`,
> ใช้ `.env` production ที่รหัส MinIO **ต่างจากเครื่อง dev**, คืนข้อมูลลง DB/volume ที่ว่าง แล้วผล
> - จำนวนแถว **ทุกตาราง + gold view + alembic version ตรงต้นทาง 100%** ทั้งหลัง restore และหลัง backend boot
> - หลักฐาน **35/35 ไฟล์** เปิดผ่าน `/api` ได้ และ sha256 ตรงต้นทางทุกไฟล์ · login admin/staff/นิสิต ผ่าน
> - MinIO console เข้าด้วยรหัสใหม่ได้ (204) · รหัสเดิมของเครื่อง dev ถูกปฏิเสธ (401)
>
> ข้อมูล ณ วันทดสอบ: นิสิต **2,033** คน = 2,031 จาก xlsx + 2 ที่เพิ่มทีหลัง (662021052, 662021054) ·
> participation 30,497 · raw_file 35 · DB dump 447 KB · MinIO 2.2 MB · web 15 MB

ทำไมต้องย้ายข้อมูล: เซิร์ฟเวอร์เริ่มจาก DB ว่าง → `seed.py` จะสร้างนิสิตเดโมชุดอื่น, นิสิตจริงมาจาก xlsx
ที่ไม่อยู่ใน git และถ้าไม่ย้าย volume MinIO รูปหลักฐานจะขึ้น "ไม่พบไฟล์ในที่จัดเก็บ"

---

## A. ที่เครื่อง dev — **PowerShell เท่านั้น**

Git Bash แปลง argument ที่ขึ้นต้นด้วย `/` เป็น path ของ Windows: `/api` → `C:/Program Files/Git/api`
(แอปล็อกอินไม่ได้) และ `/tmp/demo.dump` ใน `docker compose exec` → `C:/Users/.../Temp/demo.dump`
(pg_dump/pg_restore หาไฟล์ไม่เจอ) — เจอทั้งสองแบบระหว่าง dry-run

**1. build frontend** (ข้ามได้ถ้าไม่ได้แก้ frontend ตั้งแต่ build ล่าสุด)

```powershell
cd "C:\Intelligent Data Lake for Student Activity Participation Tracking\frontend"
flutter build web --dart-define=API_BASE_URL=/api --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/ --no-web-resources-cdn
cd ..
(Select-String -Path frontend\build\web\main.dart.js -Pattern "Program Files").Count            # ต้อง 0
(Select-String -Path frontend\build\web\main.dart.js -Pattern "gstatic.com/flutter-canvaskit").Count  # ต้อง 0
```

**2–3. แพ็ก frontend + ดึงข้อมูลเดโมออก** — เขียนลงโฟลเดอร์ **นอก repo** เพราะ dump มีข้อมูลนิสิต
(ไฟล์ `*.dump` ไม่อยู่ใน .gitignore เผลอ commit ได้) · ทำตอนจะอัปจริง ข้อมูลจะได้เป็นล่าสุด

```powershell
cd "C:\Intelligent Data Lake for Student Activity Participation Tracking"
$T = "$env:USERPROFILE\deploy-052"; New-Item -ItemType Directory -Force $T | Out-Null

tar czf "$T\web.tgz" -C frontend/build web

docker compose exec -T db pg_dump -U postgres -Fc activity_lake -f /tmp/demo.dump
docker compose cp db:/tmp/demo.dump "$T\demo_db.dump"
docker compose exec -T db rm /tmp/demo.dump

# :ro = อ่านอย่างเดียว ไม่แตะ volume จริง
docker run --rm -v intelligentdatalakeforstudentactivityparticipationtracking_minio_data:/data:ro -v "${T}:/out" alpine tar czf /out/demo_minio.tgz -C /data .

Get-ChildItem $T   # ต้องมี 3 ไฟล์: web.tgz, demo_db.dump, demo_minio.tgz
```

**4. ส่งขึ้นเซิร์ฟเวอร์**

```powershell
scp "$T\web.tgz" "$T\demo_db.dump" "$T\demo_minio.tgz" s662021052@miscis.scidi.tsu.ac.th:/var/www/662021052/
```

---

## B. บนเซิร์ฟเวอร์ (bash)

**5. ดึงโค้ด** — repo เป็น public, clone ได้โดยไม่ต้องใส่รหัส (ทดสอบแล้ว)

```bash
cd /var/www/662021052
git clone https://github.com/662021052-debug/intelligent-data-lake-student-activity.git app   # ครั้งแรก
cd app
# ครั้งต่อไป: cd /var/www/662021052/app && git pull
```

ชื่อโฟลเดอร์ `app` = ชื่อ compose project → volume จะชื่อ **`app_db_data`** / **`app_minio_data`**
(ยืนยันแล้วใน dry-run — ถ้าเปลี่ยนชื่อโฟลเดอร์ ชื่อ volume ในข้อ 8 ต้องเปลี่ยนตาม)

**6. `.env` production** (ที่ `/var/www/662021052/app/.env` ห้าม commit)

สร้างไฟล์ด้วย editor (`nano .env`) ตามแม่แบบนี้ — **ทุกค่าใน `<...>` เป็น placeholder ต้องแทนเอง**
เอกสารนี้ไม่มีค่าจริงแม้แต่ตัวเดียว อย่า copy `.env` จากเครื่อง dev ขึ้นไป

```dotenv
# ---- ต้องตั้ง ----
JWT_SECRET=<สุ่มใหม่ ≥ 64 ตัวอักษร>
PUBLIC_APP_BASE_URL=http://miscis.scidi.tsu.ac.th:5052
CORS_ORIGINS=http://miscis.scidi.tsu.ac.th:5052
MINIO_ROOT_USER=<ชื่อผู้ใช้ MinIO ใหม่ ≥ 3 ตัวอักษร>
MINIO_ROOT_PASSWORD=<สุ่มใหม่ ≥ 8 ตัวอักษร>

# ---- ปิดไว้ก่อน (stub = ไม่ต่อบริการภายนอก) ----
LLM_BACKEND=stub
EMAIL_BACKEND=stub
NOTIFY_SCHEDULER_ENABLED=false

# ---- เปิดทีหลังถ้าต้องการ ----
# LLM_BACKEND=gemini
# GEMINI_API_KEY=<API key จาก Google AI Studio>
# EMAIL_BACKEND=smtp
# SMTP_HOST=<smtp host>
# SMTP_PORT=587
# SMTP_USER=<บัญชีผู้ส่ง>
# SMTP_PASSWORD=<app password ของบัญชีผู้ส่ง>
# SMTP_FROM=<อีเมลผู้ส่ง>
```

สุ่มค่าลับบนเซิร์ฟเวอร์ (พิมพ์ออกจอแล้วนำไปวางใน `.env` — อย่าเก็บไว้ในไฟล์อื่นหรือ commit):

```bash
openssl rand -hex 32    # ใช้เป็น JWT_SECRET
openssl rand -hex 16    # ใช้เป็น MINIO_ROOT_PASSWORD
chmod 600 .env
grep -v '^#' .env | grep -c '<'   # ต้องได้ 0 = ไม่มี placeholder หลงเหลือในบรรทัดที่ใช้งาน
```

- รหัส MinIO ตั้งใหม่ได้เลย ไม่ต้องตรงกับเครื่อง dev (ทดสอบแล้ว: volume ที่ย้ายมาเปิดด้วยรหัสใหม่ได้ รหัสเดิมของ dev ใช้ไม่ได้)
- `NOTIFY_SCHEDULER_ENABLED=true` = ส่งอีเมลจริงถึงนิสิตทุกคนที่มีอีเมล — เปิดเมื่อพร้อมเท่านั้น

**7. วางไฟล์ frontend** — ถ้าข้าม docker จะสร้างโฟลเดอร์ว่างให้แล้ว nginx ตอบ 403

```bash
mkdir -p frontend/build && tar xzf ../web.tgz -C frontend/build && chmod -R a+rX frontend/build/web
ls frontend/build/web/index.html
```

**8. คืนข้อมูลเดโม (ครั้งแรกเท่านั้น)** — ต้องทำ **ก่อน** ขึ้น backend ครั้งแรก

```bash
docker compose up -d db minio
until docker compose exec -T db pg_isready -U postgres -q; do sleep 2; done

docker compose cp ../demo_db.dump db:/tmp/demo.dump
docker compose exec -T db pg_restore -U postgres -d activity_lake --clean --if-exists --no-owner /tmp/demo.dump
echo "pg_restore exit=$?"      # ต้อง 0 (DB ว่าง = ไม่มี warning เลยใน dry-run)
docker compose exec -T db rm /tmp/demo.dump

docker compose stop minio      # หยุดก่อนเขียนทับข้อมูลใน volume
docker volume ls --filter label=com.docker.compose.project=app   # ต้องเห็น app_minio_data
docker run --rm -v app_minio_data:/data -v "$PWD/..":/in alpine tar xzf /in/demo_minio.tgz -C /data
```

**9. ขึ้นทั้งระบบ**

```bash
df -h /var/lib/docker          # backend image ~10.7 GB (easyocr + torch + โมเดลไทย)
docker compose up -d --build
```

build ใช้ **439 วินาที** บนเครื่อง dev ที่มี layer cache อยู่แล้วบางส่วน — บนเซิร์ฟเวอร์ที่ไม่มี cache จะนานกว่านี้
(ต้อง pip install + โหลดโมเดล OCR) · backend พร้อมภายใน ~3 วินาทีหลังคอนเทนเนอร์ start
log ต้องมี `มีข้อมูลอยู่แล้ว ข้ามการ seed` (seed ไม่แตะข้อมูลที่ย้ายมา — จำนวนแถวหลัง boot ตรงต้นทาง 100%)

**10. ตรวจหลังขึ้นระบบ**

```bash
docker compose ps                                   # published ต้องมีแค่ 5052 (web) และ 9052 (minio console)
curl -s localhost:5052/api/health                   # {"status":"ok"}

docker compose exec -T db psql -U postgres -d activity_lake -c \
  "SELECT (SELECT count(*) FROM student) AS student, (SELECT count(*) FROM participation) AS participation, (SELECT count(*) FROM raw_file) AS raw_file;"
# ต้องตรงกับเครื่อง dev ตอน dump (วันทดสอบ: 2033 / 30497 / 35)

# หลักฐานทุกไฟล์ต้องเปิดได้ (ผลต้องเป็น "<จำนวน raw_file> 200" บรรทัดเดียว)
read -r -s -p "รหัสผ่าน admin: " ADMIN_PASS; echo
TOKEN=$(curl -s -X POST localhost:5052/api/auth/login --data-urlencode "username=admin" --data-urlencode "password=$ADMIN_PASS" | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
for pid in $(docker compose exec -T db psql -U postgres -d activity_lake -t -A -c "SELECT DISTINCT participation_id FROM raw_file" | tr -d '\r'); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN" "localhost:5052/api/participations/$pid/evidence"
done | sort | uniq -c
```

จากเครื่องนอก: เปิด `http://miscis.scidi.tsu.ac.th:5052/` → login admin / staff / นิสิต → ตรวจหลักฐาน → กด "ตรวจ" เห็นรูป

MinIO console: 9052 ไม่ได้เปิดออกนอก → `ssh -L 9052:localhost:9052 s662021052@miscis.scidi.tsu.ac.th`
แล้วเปิด `http://localhost:9052` ด้วย `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` ใน `.env` ของเซิร์ฟเวอร์ (ครั้งแรกจะมีหน้าต่าง license AGPL ให้กด Acknowledge)

**11. ลบไฟล์ที่ส่งขึ้นไป** (มีข้อมูลนิสิต) — ทั้งบนเซิร์ฟเวอร์และเครื่อง dev

```bash
rm /var/www/662021052/demo_db.dump /var/www/662021052/demo_minio.tgz
```
```powershell
Remove-Item "$env:USERPROFILE\deploy-052\demo_db.dump", "$env:USERPROFILE\deploy-052\demo_minio.tgz"
```

---

## อัปเดตรอบถัดไป (ไม่ต้องย้ายข้อมูลซ้ำ)

- `cd /var/www/662021052/app && git pull`
- แก้ frontend → ทำข้อ 1, `tar czf` web, scp, แล้ว `rm -rf frontend/build/web && tar xzf ../web.tgz -C frontend/build`
  ไม่ต้อง restart (nginx อ่านไฟล์ตรง, `index.html` เป็น no-store)
- แก้ backend → `docker compose up -d --build backend`
- **ห้าม** `docker compose down -v` บนเซิร์ฟเวอร์ — `-v` ลบ volume = ข้อมูลเดโมหายทั้งหมด

## ข้อควรรู้

- รหัส DB `postgres:postgres` ยังเขียนตรงใน `docker-compose.yml` (ไม่อ่านจาก .env) — ความเสี่ยงต่ำเพราะ db ไม่มี host port
- บัญชีเดโม (admin / staff / นิสิต) ยังใช้รหัสผ่านเริ่มต้นตาม README (คงข้อมูลจำลองตามสเปก) — เปลี่ยนก่อนใช้งานจริง
- กล้องสแกน QR ใช้ไม่ได้บน HTTP → ใช้ "กรอกรหัสกิจกรรม" แทน
- เฉพาะตอน dry-run บน Windows: clone ลงโฟลเดอร์ที่ path ยาวจะ checkout ไม่ครบ (MAX_PATH)
  ต้อง `git -c core.longpaths=true clone` — เซิร์ฟเวอร์ Linux ไม่มีปัญหานี้
