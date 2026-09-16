# Prompt สำหรับ Claude Code — Deploy ทั้ง stack หลัง port เดียว (5052) บนเซิร์ฟเวอร์มหาลัย

## บริบทเซิร์ฟเวอร์ (จากเจ้าหน้าที่)
- SSH: `ssh s662021052@miscis.scidi.tsu.ac.th` (port 22) · path `/var/www/662021052`
- รัน `docker compose up -d --build` ได้ (มี Docker)
- **เปิดออกนอกได้ port เดียว: 5052** · URL เข้าใช้งาน: `http://miscis.scidi.tsu.ac.th:5052/` (HTTP ไม่ใช่ HTTPS)
- **แอปทั้งหมดต้องเข้าถึงผ่าน 5052 ทางเดียว** → ต้องมี reverse proxy

**คงข้อมูลจำลองไว้ (demo) ไม่ต้องล้าง · ไม่แตะ business logic**
ทำเป็นเฟส หยุดให้ตรวจ · **ทดสอบ local ให้ผ่านก่อน แล้วค่อยอัปขึ้น server**

---

## เฟส 0 — AUDIT (อ่านอย่างเดียว) รายงานกลับก่อน
1. **frontend เสิร์ฟยังไงตอนนี้** — อยู่ใน compose หลักไหม หรือรันแยก (devserver 8080)? มี nginx serve build/web ไหม?
2. **ไฟล์หลักฐานส่งถึงเบราว์เซอร์ยังไง** (สำคัญสุด) — backend stream ไฟล์เอง (ผ่าน /api) หรือคืน **presigned URL ของ MinIO** ที่ชี้ host (localhost:9052 / minio:9000)? ถ้าเป็น presigned จะพังเมื่อไม่เปิด MinIO ออกนอก
3. **frontend เรียก API ที่ base URL ไหน** — hardcode localhost:8000? ตั้งผ่าน --dart-define? ไฟล์ไหน
4. **CORS ตั้งที่ไหน** ในโค้ด backend · ค่าปัจจุบัน
5. host port ที่ผูกใน docker-compose ตอนนี้ (db 5052, minio 9052/10052, backend 8000)

**รายงานกลับก่อน แล้วหยุด** — ผลข้อ 2 ตัดสินว่าต้องแก้การเสิร์ฟไฟล์ไหม

---

## เฟส 1 — reverse proxy บน 5052 + compose แบบ port เดียว
- เพิ่ม service **`web` (nginx)** ผูก host **`5052:80`**:
  - เสิร์ฟไฟล์ Flutter web (build/web) ที่ `/`
  - proxy `/api/` → `backend:8000` (ภายใน)
  - ถ้าไฟล์หลักฐานเป็น presigned MinIO (จากเฟส 0): เพิ่ม proxy path เช่น `/files/` → `minio:9000` **หรือ** เปลี่ยนให้ backend stream ไฟล์ผ่าน `/api` (เลือกทางที่กระทบน้อย รายงานว่าเลือกอะไร)
- **เอา host port ของ db / backend / minio ออก** (internal only) — เหลือแค่ `web` เปิด 5052
  - db: ยกเลิกที่เพิ่ง set 5052 (กลับเป็น internal เท่านั้น) · minio: internal เท่านั้น
- ทุก service อยู่ Docker network เดียวกัน · backend ต่อ db:5432 / minio:9000 ภายในเหมือนเดิม

หยุดให้ตรวจ

## เฟส 2 — frontend + ค่าคอนฟิกให้ตรง URL จริง
- **frontend API base = path สัมพัทธ์ `/api`** (ผ่าน proxy จึงไม่ผูกกับ host ใด ๆ) build ด้วยค่านี้
  - ถ้าโค้ดใช้ absolute URL ให้เปลี่ยนเป็น relative หรือ `--dart-define=API_BASE_URL=/api`
- **APP_BASE_URL** (ลิงก์อีเมล) = `http://miscis.scidi.tsu.ac.th:5052`
- **CORS** อนุญาต `http://miscis.scidi.tsu.ac.th:5052` (จริง ๆ same-origin ผ่าน proxy อาจไม่ต้อง แต่ตั้งไว้กันเหนียว)
- **ไฟล์หลักฐาน** URL ที่ส่งให้เบราว์เซอร์ต้อง resolve ผ่าน 5052 (ไม่ใช่ localhost:9052) — ยืนยันตามทางที่เลือกในเฟส 1
- **วิธี build frontend**: ทำ multi-stage Dockerfile (Flutter build → คัดลอกเข้า nginx) เพื่อให้ `docker compose up --build` บน server สร้างครบ · ถ้า image หนัก/ช้าเกิน ให้ fallback เป็น build local แล้ว bind-mount build/web (รายงานว่าเลือกอะไร)

หยุดให้ตรวจ

## เฟส 3 — ทดสอบ local จำลอง server ก่อนอัป
- รัน compose ใหม่บนเครื่อง เข้าผ่าน **port เดียว** (เช่น localhost:5052) แล้วยืนยัน:
  - หน้าเว็บโหลด, login ครบ 3 role
  - แดชบอร์ดมีข้อมูล, สมัคร/ปฏิทิน, **อัปโหลด + เปิดดูไฟล์หลักฐานได้** (จุดเสี่ยงสุด)
  - เช็ค network ในเบราว์เซอร์: ไม่มี request ไป localhost:8000 / :9052 หลุด (ทุกอย่างผ่าน 5052)
- เทส/build ผ่าน · commit push
- **แล้วสรุปขั้นตอนอัปขึ้น server** (git clone/pull บน server → สร้าง .env production → docker compose up -d --build) เป็น checklist สั้น ๆ

## ข้อควรระวัง
- คงข้อมูลจำลอง demo ไว้
- .env production (JWT/SMTP/DB/MinIO/APP_BASE_URL) สร้างบน server ห้าม commit
- ไม่เปิด host port อื่นนอกจาก 5052

เริ่มเฟส 0 (audit) ก่อน รายงานกลับ หยุดให้ตรวจ
