# ฟอนต์สำรองของ Flutter engine (self-hosted)

CanvasKit ไม่มีฟอนต์ระบบ เจอตัวอักษรที่ฟอนต์หลัก (Sarabun) ไม่มี เช่น ✓ → อีโมจิ
หรือข้อความที่ไม่ได้ระบุฟอนต์ จะไปดาวน์โหลดฟอนต์สำรองจาก `fontFallbackBaseUrl`
ซึ่งดีฟอลต์คือ `https://fonts.gstatic.com/s/` — บนเครือข่ายที่บล็อก Google
ตัวอักษรพวกนั้นจะกลายเป็นกล่องสี่เหลี่ยม

`web/flutter_bootstrap.js` ชี้ `fontFallbackBaseUrl` มาที่โฟลเดอร์นี้ (`/fonts/gstatic/`)
โครง path ต้องตรงกับบน gstatic ทุกตัวอักษร เพราะ engine ต่อ path เองจากตารางภายใน

## รายการไฟล์ (เก็บจากการเปิดทุกเมนูของ admin / staff / นิสิต เมื่อ 2026-09-16)

| path | ใช้กับ | license |
|---|---|---|
| `roboto/v32/…` | ข้อความที่ไม่ได้ระบุฟอนต์ | Apache-2.0 |
| `notosansthai/v25/…` | ตัวอักษรไทยนอก Sarabun | OFL-1.1 |
| `notosanssc/v37/….87.woff2` | สัญลักษณ์ในชุดย่อยของ Noto Sans SC (เช่น ✓) | OFL-1.1 |
| `notosanssymbols2/v24/…` | ลูกศร/สัญลักษณ์ | OFL-1.1 |
| `notocoloremoji/v32/….{2,3,4,9}.woff2` | อีโมจิ | OFL-1.1 |

## ถ้าอัปเกรด Flutter หรือมีหน้าจอใหม่

ชื่อเวอร์ชัน (`v32`, `v25`, …) และเลขชุดย่อยผูกกับ engine แต่ละรุ่น อัปเกรด Flutter แล้ว
ต้องเก็บรายชื่อใหม่: เปิดแอปโดยไม่บล็อกเน็ต ดู request ที่ไป `fonts.gstatic.com`
ใน DevTools → Network แล้วดาวน์โหลดไฟล์ที่ขาดมาวางตาม path เดิม
ไฟล์ที่ไม่มี = ตัวอักษรนั้นเป็นกล่องเฉพาะตัว แอปไม่ล่ม
