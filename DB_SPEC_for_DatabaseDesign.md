# ข้อมูลตั้งต้นสำหรับเขียน "เอกสารการออกแบบฐานข้อมูล"

> **Intelligent Data Lake for Student Activity Participation Tracking**
> ระบบติดตามการเข้าร่วมกิจกรรมเสริมหลักสูตรของนิสิต มหาวิทยาลัยทักษิณ
>
> เอกสารนี้ **ไม่ใช่เอกสารการออกแบบฐานข้อมูล** แต่เป็น *ข้อมูลตั้งต้น* ที่ต้องป้อนให้ Claude
> เพื่อให้เขียนเอกสารนั้นได้โดยไม่ต้องเดา
>
> ข้อมูลทุกบรรทัดสกัดจากของจริง ณ 2026-08-03 — `backend/app/models.py`, `backend/alembic/versions/`,
> `backend/app/gold.py` และ **query จาก Postgres ที่รันอยู่จริง** (`information_schema`, `pg_constraint`, `pg_indexes`)

---

## 0. อ่านก่อน — ของที่มีอยู่แล้ว อย่าให้ Claude เขียนซ้ำ

`SYSTEM_SPEC_for_Diagrams.md` **§2 (บรรทัด 167–341)** มีครบแล้วและถูกต้อง:

| มีแล้วใน SYSTEM_SPEC §2 | รายละเอียด |
|---|---|
| §2.1 พจนานุกรมข้อมูลระดับ logical | ทุกตาราง ทุกคอลัมน์ ชนิด PK/FK/UNIQUE/INDEX |
| §2.2 ความสัมพันธ์ + cardinality | ครบ 11 เส้น พร้อมคำอธิบาย associative entity |
| §2.3 Gold Layer star schema | fact 1 + dim 5 + data mart 2 |
| §2.4 โครงสร้างเกณฑ์ชั่วโมง | 5 หมวด 13 หมวดย่อย รวม 60 ชม. |

`ARCHITECTURE_SPEC_for_Diagrams.md` §6 มี Medallion data flow (Bronze→Silver→Gold) แล้วเช่นกัน

**สั่ง Claude ว่า:** ให้ *อ้างอิงและต่อยอด* จาก §2 ไม่ใช่เขียนตาราง ER ใหม่ทั้งชุด สิ่งที่ยังขาดคือหัวข้อ
ในส่วนที่ 1–7 ด้านล่าง ซึ่งเป็นเนื้อหาระดับ **physical design + design rationale** ที่เอกสาร ER
ไม่ได้ครอบคลุม

---

## 1. สิ่งที่ยังไม่มีที่ไหนเลย (นี่คือเนื้อหาหลักของเอกสารใหม่)

1. **Physical design จริงบน Postgres** — ชื่อ constraint ชื่อ index ชนิดข้อมูลจริง
2. **กฎความถูกต้องที่บังคับใน "โค้ด" ไม่ใช่ใน "ฐานข้อมูล"** ← สำคัญที่สุด เป็นจุดที่กรรมการมักถาม
3. **ประวัติวิวัฒนาการสคีมา** (Alembic 7 revision)
4. **การวิเคราะห์ Normalization** (1NF/2NF/3NF) + จุดที่จงใจ denormalize
5. **ความต่างระหว่าง SQLite (dev/test) กับ PostgreSQL (prod)**
6. **เหตุผลว่าทำไม Gold Layer เป็น VIEW ไม่ใช่ TABLE**
7. **ความปลอดภัยระดับข้อมูล** — คอลัมน์อ่อนไหว + row-level access

---

## 2. Physical design จริง (query จาก Postgres ที่รันอยู่)

### 2.1 ภาพรวมออบเจ็กต์

| ประเภท | จำนวน | รายชื่อ |
|---|---:|---|
| BASE TABLE | 9 | `student`, `user`, `hourcategory`, `hoursubcategory`, `activity`, `participation`, `raw_file`, `silver_evidence_ocr`, `alembic_version` |
| VIEW (Gold) | 8 | `gold_fact_participation`, `gold_dim_student`, `gold_dim_activity`, `gold_dim_hour_category`, `gold_dim_subcategory`, `gold_dim_date`, `gold_student_hours`, `gold_activity_catalog` |
| ตารางนอก Alembic | 1 (มีเงื่อนไข) | `rag_rule_chunk` — สร้างด้วย raw SQL ใน `app/vectorstore.py` เฉพาะเมื่อ `VECTOR_BACKEND=pgvector` (ตอนนี้ตั้งเป็น `memory` จึง **ยังไม่มีจริงในฐาน**) |

`rag_rule_chunk(id, source, chunk_index, content, embedding vector(N))` + `CREATE EXTENSION IF NOT EXISTS vector`
— ต้องระบุในเอกสารว่าเป็นตารางที่ **ไม่อยู่ใต้ Alembic** เป็นข้อจำกัดที่ตั้งใจ (ไม่อยากให้คอลัมน์ชนิด
`vector` รั่วเข้าไปใน SQLModel ซึ่งจะพังบน SQLite)

### 2.2 Index ทั้งหมด 18 ตัว

| ตาราง | Index | ชนิด |
|---|---|---|
| student | `student_pkey` / `ix_student_student_id` | PK / **UNIQUE** |
| user | `user_pkey` / `ix_user_username` | PK / **UNIQUE** |
| activity | `activity_pkey` / `ix_activity_checkin_token` | PK / **UNIQUE** |
| hourcategory | `hourcategory_pkey` | PK |
| hoursubcategory | `hoursubcategory_pkey` | PK |
| participation | `participation_pkey` / `ix_participation_student_id` / `ix_participation_activity_id` | PK / non-unique / non-unique |
| raw_file | `raw_file_pkey` / `ix_raw_file_checksum` / `ix_raw_file_participation_id` | PK / non-unique / non-unique |
| silver_evidence_ocr | `silver_evidence_ocr_pkey` / `ix_silver_evidence_ocr_raw_file_id` / `ix_silver_evidence_ocr_participation_id` | PK / non-unique / non-unique |
| alembic_version | `alembic_version_pkc` | PK |

**เหตุผลของ index ที่ไม่ใช่ PK** (ให้ Claude อธิบายในเอกสาร):
- `ix_raw_file_checksum` — ใช้ตรวจไฟล์ซ้ำ (SHA-256) ตอน OCR ตัดสินใจ `flagged`
- `ix_participation_student_id` / `_activity_id` — ใช้ทุกครั้งที่ query ชั่วโมงของนิสิตและรายชื่อผู้เข้าร่วม
- `ix_activity_checkin_token` UNIQUE — ค้นกิจกรรมจาก token ใน QR ตอนเช็กอิน

### 2.3 Foreign Key ทั้ง 11 เส้น — **ทุกเส้นเป็น `NO ACTION`**

```
activity.subcategory_id        → hoursubcategory.id
activity.created_by           → user.id
activity.approved_by          → user.id
hoursubcategory.category_id   → hourcategory.id
participation.student_id      → student.id
participation.activity_id     → activity.id
raw_file.participation_id     → participation.id
raw_file.uploaded_by          → user.id
silver_evidence_ocr.raw_file_id      → raw_file.id
silver_evidence_ocr.participation_id → participation.id
user.student_id               → student.id
```

> **ไม่มี `ON DELETE CASCADE` / `ON UPDATE CASCADE` แม้แต่เส้นเดียว** (`confdeltype = 'a'` = NO ACTION ทั้งหมด)
> การลบแบบต่อเนื่องทั้งหมดจึงถูกจัดการใน **application layer** ดูส่วนที่ 3

### 2.4 CHECK constraint ที่เขียนเองมีแค่ตัวเดียว

| Constraint | ตาราง | นิยาม | มาจาก migration |
|---|---|---|---|
| `ck_activity_max_participants_positive` | activity | `max_participants > 0` | `e4f5a6b7c8d9` |

CHECK อื่น ๆ ที่เห็นใน `information_schema` (ชื่อขึ้นต้น `2200_xxxxx_n_not_null`) เป็น NOT NULL
ที่ Postgres สร้างให้อัตโนมัติ **ไม่ใช่ business rule** — อย่าให้ Claude เอาไปนับเป็น constraint ที่ออกแบบไว้

### 2.5 ชนิดข้อมูลของ ENUM

Postgres สร้าง **native ENUM type** ให้จริง: `studentstatus`, `userrole`, `evidencestatus`,
`approvalstatus`, `ocrdecision` (เช่น `student.status` มีชนิดเป็น `studentstatus` ไม่ใช่ VARCHAR)
บน SQLite ชนิดเดียวกันนี้กลายเป็น `VARCHAR` + ตรวจค่าที่ชั้น Python เท่านั้น

### 2.6 ปริมาณข้อมูลจริง (ใช้เขียนหัวข้อ Capacity / Volumetrics)

| ตาราง | จำนวนแถว |
|---|---:|
| student | 100 |
| user | 102 (นิสิต 100 + `admin` + `staff`) |
| activity | 30 |
| participation | 1,160 |
| raw_file | 1,129 |
| silver_evidence_ocr | 1,130 |
| hourcategory | 5 |
| hoursubcategory | 13 |

---

## 3. ⭐ กฎความถูกต้องที่บังคับใน "โค้ด" ไม่ใช่ใน "ฐานข้อมูล"

**นี่คือหัวข้อที่ต้องมีในเอกสาร** เพราะเป็นช่องว่างระหว่าง conceptual design กับ physical design
และเป็นจุดที่ถูกถามบ่อยว่า "ถ้ามีคนเขียนลงฐานตรง ๆ ระบบจะพังไหม"

| # | กฎทางธุรกิจ | บังคับที่ไหน | ผลถ้ามีคน INSERT ตรงเข้าฐาน |
|---|---|---|---|
| 1 | นิสิต 1 คนสมัครกิจกรรมเดียวกันได้ครั้งเดียว | **โค้ดเท่านั้น** (`participations.py:232–239`) | ❌ เกิดแถวซ้ำได้ — **ไม่มี UNIQUE(student_id, activity_id)** |
| 2 | `activity.hours > 0` | **Pydantic เท่านั้น** (`ActivityCreate`) | ❌ ใส่ 0 หรือติดลบได้ |
| 3 | `ocr_confidence` / `match_score` อยู่ในช่วง 0–1 | **โค้ดเท่านั้น** | ❌ ใส่ 5.0 ได้ |
| 4 | `user.student_id` ต้องมีค่าเมื่อ `role='student'` และต้องเป็น NULL เมื่อ staff/admin | **โค้ดเท่านั้น** | ❌ สร้างบัญชีนิสิตที่ไม่ผูกใครได้ |
| 5 | `hours_earned` ต้องเท่ากับ `activity.hours` เมื่ออนุมัติ และเป็น 0 เมื่อ pending/rejected | **โค้ดเท่านั้น** (`extra="forbid"` กันการยัดค่าเข้ามาทาง API) | ❌ ปลอมชั่วโมงได้ |
| 6 | อนุมัติหลักฐานได้เฉพาะเมื่อมีไฟล์ Bronze แล้ว | **โค้ดเท่านั้น** | ❌ อนุมัติโดยไม่มีหลักฐานได้ |
| 7 | ลบนิสิตที่มีประวัติเข้าร่วมไม่ได้ | **โค้ด** (`students.py:280–289`) | ⚠️ FK เป็น NO ACTION → Postgres โยน FK violation ตอน commit (กันได้ แต่ error ไม่สื่อ) |
| 8 | ลบนิสิต = ต้องลบบัญชีที่ผูกอยู่ด้วย | **โค้ด** (ไม่มี CASCADE) | ⚠️ เหลือ "บัญชีกำพร้า" ที่ล็อกอินได้แต่ไม่มีข้อมูลนิสิต |
| 9 | Bronze immutable — อัปโหลดใหม่ไม่ทับของเดิม | **โค้ด** (INSERT แถวใหม่เสมอ) | — |

**ประเด็นที่ควรเขียนเป็นข้อเสนอแนะในเอกสาร**: ข้อ 1 ควรเพิ่ม
`UNIQUE (student_id, activity_id)` ที่ระดับฐานข้อมูลเพื่อกัน race condition (สองคำขอพร้อมกัน
ผ่านการตรวจในโค้ดทั้งคู่ก่อนที่ฝ่ายใดฝ่ายหนึ่งจะ commit) — ให้เสนอเป็น "ข้อจำกัดที่พบ + แนวทางปรับปรุง"
ไม่ใช่แก้โค้ดในตอนนี้

---

## 4. ประวัติวิวัฒนาการสคีมา (Alembic — ใช้เขียนหัวข้อ Schema Versioning)

| ลำดับ | Revision | เนื้อหา |
|---:|---|---|
| 1 | `9edffc436b9a` | initial schema |
| 2 | `a772953965c8` | ลบ `activity.hour_category` (free-text) — ให้ `subcategory_id` เป็น single source of truth |
| 3 | `b1c2d3e4f5a6` | เพิ่มตาราง `raw_file` (Bronze metadata / lineage) |
| 4 | `c2d3e4f5a6b7` | เพิ่ม `activity.hours` + backfill จาก `subcategory.required_hours` |
| 5 | `d3e4f5a6b7c8` | เพิ่มตาราง `silver_evidence_ocr` (ผล OCR) |
| 6 | `e4f5a6b7c8d9` | เพิ่ม CHECK `max_participants > 0` |
| 7 | `f5a6b7c8d9e0` | เพิ่ม `activity.checkin_token` (nullable → backfill uuid → NOT NULL + UNIQUE) ← **head ปัจจุบัน** |

**เกร็ดที่ควรบันทึกเป็น "ข้อควรระวังในการดูแลรักษา"**
- migration ที่ 7 ต้อง **DROP gold_* views ก่อน** `batch_alter_table` แล้วสร้างใหม่ ไม่งั้นล้มกลางคันบน SQLite
- pattern "เพิ่ม nullable → backfill → บังคับ NOT NULL" คือวิธีเพิ่มคอลัมน์บังคับกับตารางที่มีข้อมูลอยู่แล้ว

---

## 5. SQLite (dev/test) vs PostgreSQL (prod) — ต้องมีหัวข้อนี้

| ประเด็น | SQLite | PostgreSQL 16 |
|---|---|---|
| ใช้เมื่อ | dev เครื่องตัวเอง + pytest | docker compose (ค่าเริ่มต้นปัจจุบัน) |
| ENUM | เก็บเป็น VARCHAR | native ENUM type |
| ฟังก์ชันวันที่ใน Gold views | `strftime('%Y', col)` | `EXTRACT(YEAR FROM col)` / `to_char()` |
| Vector store | in-memory cosine | `pgvector` + ตาราง `rag_rule_chunk` |
| การบังคับ FK | ต้องเปิดเอง มัก NO-OP | บังคับจริง |

> `app/gold.py` มีฟังก์ชัน `_date_exprs(dialect)` ที่แตกนิพจน์วันที่ตาม dialect — ส่วนที่เหลือของ DDL
> ใช้ SQL ชุดเดียวกันทั้งสองฐาน นี่คือเหตุผลที่ Gold Layer ใช้ **prefix `gold_`** แทนการสร้าง
> Postgres schema แยก (schema แยกจะพอร์ตไป SQLite ไม่ได้)

---

## 6. ทำไม Gold Layer เป็น VIEW ไม่ใช่ TABLE

ให้ Claude เขียนเป็นหัวข้อ design decision:
- view ไม่เก็บข้อมูลซ้ำ จึงไม่มีปัญหา data ไม่ตรงกับตารางต้นทาง
- "refresh" ทำได้ด้วยการ DROP + CREATE ใหม่ (ทำตอน startup ทุกครั้ง และผ่าน `POST /gold/refresh` โดย admin)
  ซึ่งยืนหยัดแทนขั้นตอน ETL จริง
- **ข้อเสียที่ต้องระบุ**: ทุก query บนแดชบอร์ดคำนวณสดทุกครั้ง ถ้าข้อมูลโตระดับหลักแสนแถวควรเปลี่ยนเป็น
  materialized view หรือ ETL ลงตารางจริง
- fact นับเฉพาะ `evidence_status = 'approved'` เท่านั้น — เป็นกฎที่ฝังอยู่ในนิยาม view

**จุด denormalize ที่จงใจ** (ใช้ในหัวข้อ Normalization): `gold_dim_student` และ `gold_activity_catalog`
ยุบ faculty/major/category_name เข้ามาไว้ในแถวเดียว ซึ่งผิด 3NF โดยตั้งใจตามหลัก dimensional modeling
เพื่อลด join — ต้องอธิบายว่า OLTP (9 ตาราง) ทำ 3NF ส่วน OLAP (8 view) จงใจ denormalize

---

## 7. ความปลอดภัยระดับข้อมูล

| คอลัมน์ | ความอ่อนไหว | การป้องกัน |
|---|---|---|
| `user.hashed_password` | สูง | bcrypt (passlib) ไม่เคยอยู่ใน response model ใด ๆ |
| `activity.checkin_token` | สูง | ประกาศใน class `Activity` ไม่ใช่ `ActivityBase` → ไม่หลุดเข้า `ActivityCreate/Update/Read` ต้องขอผ่าน `GET /activities/{id}/checkin-qr` เท่านั้น (staff เจ้าของ/admin) |
| `raw_file.object_key` | กลาง | bucket ไม่เปิด public — ไฟล์สตรีมผ่าน backend เสมอ |
| `silver_evidence_ocr.extracted_text` | กลาง | ข้อความจากใบประกาศจริง มีชื่อ-นามสกุลนิสิต |

**Row-level access ที่ต้องอธิบาย**: นิสิตเห็นเฉพาะแถวของตัวเอง (`participation.student_id = user.student_id`),
staff เห็นเฉพาะกิจกรรมที่ตนสร้าง (`activity.created_by`), admin เห็นทั้งหมด — บังคับด้วย WHERE clause
ในโค้ด ไม่ใช่ Postgres RLS

สำหรับ Text-to-SQL ของแชตบอต: LLM ถูกจำกัดให้อ่านได้เฉพาะ CTE `my_hours` ที่กรองด้วย `student_key`
มาแล้ว (ไม่ให้แตะ `gold_student_hours` ดิบ) + ผ่าน `app/sql_guard.py` ที่ยอมเฉพาะ SELECT และ
whitelist ตาราง

---

## 8. โครงเอกสารที่แนะนำให้ Claude เขียน

```
1. บทนำ — ขอบเขต, ระบบจัดการฐานข้อมูลที่เลือกและเหตุผล
2. การออกแบบเชิงแนวคิด (Conceptual) — ER Diagram        [ดึงจาก SYSTEM_SPEC §2.1–2.2]
3. การออกแบบเชิงตรรกะ (Logical) — พจนานุกรมข้อมูล        [ดึงจาก SYSTEM_SPEC §2.1 + เติมชนิดจริงจาก §2.5 ที่นี่]
4. การวิเคราะห์ Normalization — 1NF/2NF/3NF ของ 9 ตาราง OLTP
5. การออกแบบเชิงกายภาพ (Physical) — index, constraint, ชนิดข้อมูล   [ส่วนที่ 2 ที่นี่]
6. กฎความถูกต้อง: ระดับฐานข้อมูล vs ระดับแอปพลิเคชัน       [ส่วนที่ 3 ที่นี่] ⭐
7. คลังข้อมูลเชิงมิติ (Gold Layer / Star Schema)          [SYSTEM_SPEC §2.3 + ส่วนที่ 6 ที่นี่]
8. การจัดการวิวัฒนาการสคีมา (Alembic)                    [ส่วนที่ 4 ที่นี่]
9. ความปลอดภัยและการเข้าถึงข้อมูล                        [ส่วนที่ 7 ที่นี่]
10. ปริมาณข้อมูลและประสิทธิภาพ                            [ส่วนที่ 2.6 ที่นี่]
11. ข้อจำกัดที่พบและแนวทางปรับปรุง                        [ส่วนที่ 3 + 6 + 9 ที่นี่]
```

---

## 9. เรื่องที่ต้องตัดสินใจก่อน — Claude ตอบแทนไม่ได้

| # | คำถาม | ทำไมถึงสำคัญ |
|---|---|---|
| 1 | เอกสารนี้ส่งใคร — อาจารย์ที่ปรึกษา / กรรมการสอบ / เป็นภาคผนวกของปริญญานิพนธ์? | กำหนดความลึกและระดับความเป็นทางการ |
| 2 | ต้องมี **DDL เต็ม (`CREATE TABLE ...`)** เป็นภาคผนวกไหม? | ถ้าต้องมี ให้ดัมพ์จาก `pg_dump --schema-only` จะได้ตรงของจริง 100% |
| 3 | หัวข้อ Normalization ต้องแสดง **ขั้นตอนการแตกตาราง** (UNF→1NF→2NF→3NF) หรือแค่ยืนยันว่าผลลัพธ์เป็น 3NF? | อย่างแรกยาวกว่ามากและต้องสมมติตารางตั้งต้นขึ้นมา |
| 4 | ให้เขียน **ภาษาไทยล้วน** หรือไทย-อังกฤษปนแบบเอกสารเดิม? | เอกสาร SPEC ที่มีอยู่เป็นไทยผสมศัพท์อังกฤษ |
| 5 | ให้ **เสนอการแก้ไข** (เช่น เพิ่ม UNIQUE, เพิ่ม CASCADE, ย้ายไป materialized view) หรือให้บรรยายของที่มีอยู่อย่างเดียว? | เปลี่ยนน้ำเสียงเอกสารทั้งฉบับ |
| 6 | **กฎการนับชั่วโมงที่ยังค้างอยู่** — นับครบเมื่อได้ชั่วโมงรวมของหมวด หรือต้องครบทุกหมวดย่อยด้วย? | ยังไม่ยืนยันกับอาจารย์ — กระทบนิยาม `gold_student_hours.completed` ที่ปัจจุบันใช้ยอดรวมของหมวด |

---

## 10. คำสั่งที่แนะนำให้พิมพ์ต่อ

```
อ่าน DB_SPEC_for_DatabaseDesign.md + SYSTEM_SPEC_for_Diagrams.md §2
แล้วเขียนเอกสารการออกแบบฐานข้อมูลตามโครงในข้อ 8
ตอบข้อ 9 ก่อน: [ใส่คำตอบ 6 ข้อ]
```
