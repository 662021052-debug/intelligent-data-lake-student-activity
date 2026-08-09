# FIX: (1) ห้ามกิจกรรมย้อนหลัง  (2) admin เพิ่มประเภทหมวดชั่วโมงได้

มี 2 งานในไฟล์นี้ ทำทีละส่วนแล้วหยุดให้ตรวจก่อน commit

---

## งานที่ 1 — ห้ามสร้าง/แก้กิจกรรมเป็นวันย้อนหลัง

### กติกา
- ตอน **สร้าง** กิจกรรม: `start_at` ต้องเป็นวันนี้หรืออนาคตเท่านั้น (ห้าม < วันนี้)
- ตอน **แก้ไข** กิจกรรม: ห้ามเปลี่ยน `start_at` ไปเป็นวันที่ผ่านมาแล้ว
- บังคับทั้ง **ฝั่ง backend** (กันจริง) และ **ฝั่ง UI** (กันตั้งแต่แรก ให้ UX ดี)

### Backend (FastAPI)
ใน validation ของ `POST /activities` และ `PUT /activities/{id}`:
```python
from datetime import datetime, timezone, timedelta

TZ_TH = timezone(timedelta(hours=7))

def _validate_not_backdated(start_at: datetime):
    now_th = datetime.now(TZ_TH)
    # เทียบเป็นเวลาไทย เผื่อ start_at เก็บ UTC ให้ .astimezone(TZ_TH) ก่อน
    start_th = start_at.astimezone(TZ_TH) if start_at.tzinfo else start_at.replace(tzinfo=TZ_TH)
    if start_th < now_th:
        raise HTTPException(status_code=400, detail="ไม่สามารถตั้งวันเวลากิจกรรมเป็นอดีตได้")
```
เรียก `_validate_not_backdated(payload.start_at)` ทั้งตอน create และ update
> หมายเหตุ: เทียบให้สอดคล้องกับที่เราแก้ timezone ไปแล้ว — ระบบเก็บ UTC ต้องแปลงเป็นเวลาไทยก่อนเทียบ ไม่งั้นเพี้ยน 7 ชม.

### UI (Flutter)
ในหน้าฟอร์มสร้าง/แก้กิจกรรม ตอนเปิด date picker:
```dart
showDatePicker(
  context: context,
  initialDate: existing?.startAt ?? DateTime.now(),
  firstDate: DateTime.now(),      // ← ล็อกไม่ให้เลือกวันก่อนวันนี้
  lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
);
```
- ถ้าเป็นหน้าแก้ไขและกิจกรรมเดิมเป็นอดีตอยู่แล้ว ให้ยังแก้ field อื่นได้ แต่ถ้าจะแก้วัน ต้องเลือกวันนี้ขึ้นไปเท่านั้น
- ถ้า backend ตอบ 400 ให้แสดงข้อความ error ใต้ช่องวันที่ ไม่ใช่ SnackBar แดงเฉยๆ

---

## งานที่ 2 — admin เพิ่ม/แก้/ลบ ประเภทหมวดชั่วโมงกิจกรรมได้

ปัจจุบันมีตาราง `hourcategory` (หมวดใหญ่) และ `hoursubcategory` (หมวดย่อย) อยู่แล้ว แต่ยังไม่มีหน้าให้ admin จัดการ ต้องเพิ่ม CRUD

### Backend — เพิ่ม endpoint (admin เท่านั้น)
```
POST   /hour-categories              สร้างหมวดใหญ่ (name, required_hours)
PUT    /hour-categories/{id}         แก้หมวดใหญ่
DELETE /hour-categories/{id}         ลบ (กันลบถ้ามีหมวดย่อย/กิจกรรมผูกอยู่ → 400)
POST   /hour-subcategories           สร้างหมวดย่อย (category_id, name, required_hours)
PUT    /hour-subcategories/{id}      แก้หมวดย่อย
DELETE /hour-subcategories/{id}      ลบ (กันลบถ้ามีกิจกรรมผูกอยู่)
```
- ทุก endpoint ตรวจ JWT ว่า role == admin
- ลบแบบปลอดภัย: ถ้ามี FK ผูกอยู่ (หมวดย่อยใต้หมวดใหญ่ หรือกิจกรรมใต้หมวดย่อย) ให้ตอบ 400 พร้อมข้อความ ไม่ลบทิ้งจนข้อมูลพัง

### UI (Flutter) — หน้าใหม่ "จัดการหมวดชั่วโมงกิจกรรม"
- เข้าถึงได้เฉพาะ admin (เพิ่มเมนู/ปุ่มในหน้า admin)
- แสดงหมวดใหญ่เป็นรายการ กดเข้าไปเห็นหมวดย่อยข้างใน
- มีปุ่มเพิ่ม/แก้/ลบ ทั้งสองระดับ พร้อม dialog กรอก name + required_hours
- reuse pattern หน้า list เดิม (search + pagination) ให้หน้าตากลมกลืน

### เชื่อมกับฟอร์มกิจกรรม
หลังเพิ่มหมวดใหม่ ตอนสร้าง/แก้กิจกรรม dropdown เลือก `subcategory_id` ต้องดึงรายการหมวดล่าสุดมาแสดง (ไม่ hardcode)

---

## ทดสอบหลังทำเสร็จ
งานที่ 1: ลองสร้างกิจกรรมวันเมื่อวาน → ต้องขึ้น error สร้างไม่ได้ / date picker เลือกวันย้อนหลังไม่ได้
งานที่ 2: login admin → เพิ่มหมวดใหม่ 1 อัน → กลับไปสร้างกิจกรรมต้องเห็นหมวดใหม่ใน dropdown

## ทำเสร็จแต่ละงานแล้วหยุดให้ฉันตรวจก่อน
