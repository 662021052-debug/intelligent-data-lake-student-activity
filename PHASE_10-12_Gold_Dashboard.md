# สเปก Phase 10–12 สำหรับ Claude Code — Gold Layer + Executive Dashboard (วัตถุประสงค์ 5.3)

> วิธีใช้: วางไฟล์นี้ในโฟลเดอร์โปรเจกต์ แล้วสั่ง Claude Code:
> "อ่าน PHASE_10-12_Gold_Dashboard.md แล้วทำทีละ Phase เริ่ม Phase 10 หยุดให้ฉันตรวจก่อนไป Phase ถัดไป"
>
> ต่อยอดจาก Phase 1–9 + FIXLIST · บังคับกฎที่ backend เสมอ · เขียน pytest คุมทุก endpoint

---

## แนวคิด

Dashboard เป็นชั้น **Gold** ของ Medallion Architecture — ต้องไม่ query ตาราง operational ตรง ๆ แต่ให้สร้าง **Gold Layer (Star Schema)** ที่ปรับให้เหมาะกับการวิเคราะห์ก่อน แล้ว Dashboard ค่อยอ่านจาก Gold นี้ (ตอบกรรมการได้ว่า Gold Layer อยู่ตรงไหน + เผื่อเชื่อม Power BI/Metabase ในอนาคต)

**ขอบเขตตามข้อเสนอ (6.6):** ร้อยละนิสิตที่ผ่านเกณฑ์ · กลุ่มเสี่ยง · กิจกรรมที่คนเข้าร่วมน้อย · drill-down รายคณะ/ชั้นปี · เปรียบเทียบแนวโน้ม

---

# Phase 10 — Gold Layer (Star Schema)

1. สร้าง **schema/prefix `gold_`** ใน Postgres สำหรับชั้นวิเคราะห์ (แยกจาก operational)
2. สร้างเป็น **SQL views** (หรือ materialized views) รูปแบบ Star Schema — นับเฉพาะ participation ที่ `evidence_status = approved`:
   - `gold_fact_participation` (fact): participation_id, student_key, activity_key, subcategory_key, date_key, hours_earned, evidence_status
   - `gold_dim_student`: student_key, รหัสนิสิต, ชื่อ, คณะ, สาขา, ชั้นปี, สถานะ
   - `gold_dim_activity`: activity_key, ชื่อ, ประเภท, subcategory, hours, approval_status
   - `gold_dim_hour_category` / `gold_dim_subcategory`: หมวด + เกณฑ์ชั่วโมง
   - `gold_dim_date`: date_key, วันที่, เดือน, ภาคเรียน, ปีการศึกษา
3. สร้าง view สรุปพร้อมใช้: `gold_student_hours` (รวมชั่วโมงต่อนิสิตต่อหมวด + ผ่านเกณฑ์ไหม)
4. ถ้าใช้ materialized view ให้มี endpoint/สคริปต์ refresh (จำลอง ETL Bronze→Silver→Gold)
5. pytest: view คืนค่าตรงกับการคำนวณจากตาราง operational, นับเฉพาะ approved

---

# Phase 11 — Dashboard API (อ่านจาก Gold Layer)

ทุก endpoint **admin เท่านั้น** (staff เห็นเฉพาะขอบเขตกิจกรรมของตัวเอง ถ้าจะเปิดให้ staff ด้วย) · รองรับ query filter `faculty`, `year_level`, `semester`

1. `GET /dashboard/overview` — KPI การ์ด:
   - จำนวนนิสิตทั้งหมด, % ที่ผ่านเกณฑ์ครบ 60 ชม., ชั่วโมงเฉลี่ยต่อคน, จำนวนกิจกรรม
2. `GET /dashboard/by-category` — ค่าเฉลี่ย earned/required ต่อ 5 หมวด (bar chart)
3. `GET /dashboard/at-risk` — **กลุ่มเสี่ยง**: นิสิตที่ชั่วโมงสะสม < X% ของเกณฑ์ (เช่น < 50%) เรียงจากน้อยไปมาก
4. `GET /dashboard/low-participation` — กิจกรรมที่มีผู้เข้าร่วมน้อย (นับเทียบ max_participants)
5. `GET /dashboard/by-faculty` — drill-down: % ผ่านเกณฑ์แยกรายคณะ + ชั้นปี
6. `GET /dashboard/trend` — แนวโน้มจำนวนการเข้าร่วมที่อนุมัติ รายเดือน/ภาคเรียน (line chart)
7. pytest: ตัวเลขตรงกับ Gold view, filter รายคณะ/ชั้นปีทำงาน, non-admin → 403

---

# Phase 12 — Dashboard UI (Flutter Web, สำหรับ admin)

1. เพิ่มการ์ด **"แดชบอร์ดผู้บริหาร"** ในหน้า Home ของ admin
2. หน้า Dashboard ประกอบด้วย:
   - **แถว KPI การ์ด** (จำนวนนิสิต, % ผ่านเกณฑ์, ชั่วโมงเฉลี่ย, จำนวนกิจกรรม)
   - **Bar chart** ชั่วโมงเฉลี่ยต่อหมวด (earned เทียบ required)
   - **Line chart** แนวโน้มการเข้าร่วมรายเดือน
   - **ตารางกลุ่มเสี่ยง** (นิสิต + คณะ + ชั่วโมงสะสม + % ที่ยังขาด) เน้นสีแดง
   - **ตารางกิจกรรมที่คนเข้าร่วมน้อย**
   - **ตัวกรอง (filter)** ด้านบน: คณะ, ชั้นปี, ภาคเรียน → drill-down
3. ใช้ไลบรารีกราฟ **`fl_chart`** (เพิ่มใน pubspec.yaml)
4. responsive: จอเล็กเรียงการ์ดเป็นแนวตั้ง, จอใหญ่เรียงเป็น grid
5. คลิกนิสิตในตารางกลุ่มเสี่ยง → เปิดหน้าชั่วโมงสะสมของนิสิตคนนั้น (ใช้ `GET /students/{id}/hours-summary` ที่มีอยู่แล้ว)

---

## เกณฑ์ว่าเสร็จ (acceptance)

- [ ] มี Gold Layer (views) ที่แยกจาก operational และนับเฉพาะ approved
- [ ] admin เปิดแดชบอร์ดเห็น KPI + กราฟ + ตารางกลุ่มเสี่ยง ครบ
- [ ] กรองรายคณะ/ชั้นปีแล้วตัวเลขเปลี่ยนตาม
- [ ] non-admin เข้า /dashboard/* → 403
- [ ] pytest ผ่านทั้งหมด

---

## หมายเหตุ

- ข้อมูล seed ตอนนี้อาจมีนิสิตที่ยังไม่มีชั่วโมงเลย (0/60) ทำให้กราฟดูว่าง — แนะนำให้ **seed participation ที่อนุมัติแล้วเพิ่ม** ให้กระจายหลากหลาย จะได้เห็นกลุ่มเสี่ยง/ผ่านเกณฑ์/แนวโน้มชัดตอนเดโม
- ในข้อเสนอเขียนว่าใช้ **Power BI** — สถาปัตยกรรมนี้เปิดทางไว้แล้ว เพราะ Gold Layer เป็น SQL view มาตรฐาน ต่อ Power BI/Metabase เข้ามาอ่านทีหลังได้ทันที แต่เฟสนี้ทำ dashboard ในแอป (Flutter) เพื่อความ integrate และเดโมง่าย — เขียนเหตุผลนี้ในเล่มได้
