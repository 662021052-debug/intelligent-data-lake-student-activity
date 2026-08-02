# แก้บั๊ก: รีเฟรชแล้วหลุด login (auth ไม่ persist ข้ามการโหลดหน้า)

## อาการ
กดรีเฟรชเบราว์เซอร์ → เด้งกลับหน้า login ทุกครั้ง แม้เพิ่งล็อกอิน

## สาเหตุ (ให้ตรวจยืนยันก่อนแก้)
JWT ถูกเก็บใน state ของแอป (ตัวแปรใน memory) เท่านั้น ไม่ได้เซฟลง browser storage → พอ Flutter web โหลดใหม่ทั้งแอปตอนรีเฟรช token หายหมด → guard เด้งไป login
- ตรวจที่: `api_service.dart` / auth service / provider ที่เก็บ token — ดูว่าตอน login สำเร็จเก็บ token ไว้ที่ไหน

## วิธีแก้
ใช้ **`shared_preferences`** (บนเว็บ map เป็น localStorage) เก็บ JWT ให้อยู่ข้ามการรีเฟรช

1. **เพิ่ม dependency** `shared_preferences` ใน pubspec.yaml
2. **ตอน login สำเร็จ** → เซฟ JWT ลง shared_preferences (คีย์เช่น `auth_token`) นอกจากเก็บใน state
3. **ตอนแอปเปิด (main.dart / เริ่ม app)** → อ่าน token จาก shared_preferences ก่อน build:
   - มี token → ตั้ง auth state จาก token นั้น แล้วเข้าแอปได้เลย (ไม่ต้อง login ใหม่)
   - ไม่มี → ไปหน้า login ตามเดิม
4. **ตอน logout** → ลบ token ออกจาก shared_preferences ด้วย
5. **token หมดอายุ / backend ตอบ 401** → ลบ token ที่เก็บไว้ + เด้งไป login (กันค้าง token เก่าที่ใช้ไม่ได้)

## ผลพลอยได้กับ deep link เช็กอิน
พอ auth persist แล้ว เคสที่คุยกันไว้ (รีเฟรชระหว่าง login แล้ว pending token หาย) จะเจ็บน้อยลงมาก เพราะผู้ใช้ยัง login อยู่หลังรีเฟรช แค่เปิดลิงก์ QR ซ้ำก็เช็กอินต่อได้เลย ไม่ต้อง login ใหม่

## เกณฑ์ว่าเสร็จ
- [ ] ล็อกอิน → กดรีเฟรช → ยัง login อยู่ หน้าเดิม ไม่เด้งออก
- [ ] logout → รีเฟรช → อยู่หน้า login (ไม่หลุดกลับเข้าไปได้เอง)
- [ ] token หมดอายุ/ผิด → เคลียร์ + ไป login ไม่ค้าง error
- [ ] deep link `/#/checkin?c=...` ตอน login อยู่แล้ว → รีเฟรช → ยังเช็กอินต่อได้
- [ ] flutter test + analyze + build web ผ่าน

## หมายเหตุความปลอดภัย
เก็บ JWT ใน localStorage มีความเสี่ยง XSS ตามทฤษฎี — สำหรับโปรเจกต์นี้ยอมรับได้และเป็นวิธีมาตรฐานของ Flutter web ถ้าอยากเข้มกว่านี้ใช้ `flutter_secure_storage` แทนได้ แต่บนเว็บมันก็ลงเอยใกล้เคียงกัน ไม่จำเป็นตอนนี้
