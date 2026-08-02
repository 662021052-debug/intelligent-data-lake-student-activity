# activity_tracking_frontend

Flutter web frontend ของระบบติดตามการเข้าร่วมกิจกรรมนิสิต — คุยกับ backend ที่
`http://localhost:8000` (ปรับตอน deploy ด้วย `--dart-define=API_BASE_URL=...`)

## รัน frontend ตอน dev

```bash
flutter build web --release --pwa-strategy=none
python devserver.py 8080          # เปิด http://localhost:8080
```

### ทำไมต้อง `--pwa-strategy=none`

ค่าเริ่มต้นของ Flutter web จะลงทะเบียน `flutter_service_worker.js` ที่ cache
`main.dart.js` ไว้แรงมาก พอ rebuild แล้ว **reload ธรรมดาจะยังได้ bundle เก่า** —
ทำให้ไล่บั๊กผิดตัว (เคสจริง: หน้าจัดการผู้ใช้ยังยิง `limit=500` ทั้งที่แก้โค้ดไปแล้ว
และ bundle ที่เสิร์ฟอยู่ก็ถูกต้องแล้ว) `--pwa-strategy=none` ทำให้ไม่มีการลงทะเบียน
service worker เลย

### ทำไมต้องใช้ `devserver.py` แทน `python -m http.server`

1. ส่ง `Cache-Control: no-store` ทุก response — reload ธรรมดาก็ได้ของใหม่เสมอ
2. เสิร์ฟ `flutter_service_worker.js` เป็นสคริปต์ที่ **unregister ตัวเอง** แล้วล้าง
   cache ทิ้ง

ข้อ 2 จำเป็นเพราะ `--pwa-strategy=none` แค่ทำให้ SW ตัวใหม่ไม่ถูกลงทะเบียน แต่
**ไม่ได้ถอน SW เก่าที่ฝังอยู่ในเบราว์เซอร์ไปแล้ว** ซึ่งจะดัก request ต่อไปเรื่อย ๆ

### ถ้ายังเห็นของเก่าอยู่

Ctrl+Shift+R ไม่พอ — hard reload ข้ามแค่ HTTP cache แต่ service worker ยังเสิร์ฟไฟล์เก่า
จาก Cache Storage อยู่ ต้องล้างที่ต้นตอ:

**F12 → Application → Storage → ติ๊ก Unregister service workers + Cache storage →
Clear site data** แล้วปิดแท็บเปิดใหม่

วิธีเช็คว่า bundle ที่เสิร์ฟเป็นตัวล่าสุดจริง (เทียบ hash กับที่ build):

```powershell
(Get-FileHash build\web\main.dart.js -Algorithm SHA256).Hash
```

หมายเหตุ: dart2js ย่อชื่อเมธอด/ตัวแปรหมด และ escape อักษรไทยเป็น `\u0e..` —
จะเช็คว่าโค้ดใหม่เข้าบันเดิลไหม ต้องหา string literal แบบ escaped ไม่ใช่ชื่อฟังก์ชัน

## เทสต์

```bash
flutter test --no-test-assets
```

`--no-test-assets` จำเป็นบนเครื่อง dev ปัจจุบัน (Windows Smart App Control บล็อก
`impellerc.exe` ที่ Flutter ใช้คอมไพล์ shader ตอนสร้าง asset bundle)
