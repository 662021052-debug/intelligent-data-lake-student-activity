# FIX: แกน X กราฟ "แนวโน้มการเข้าร่วมรายเดือน" อ่านยาก / label ซ้ำ

## ปัญหา
1. **Label ซ้ำ** — แกนล่างแสดง `2025-08 2025-08`, `2025-11 2025-11` ฯลฯ (ป้ายเดือนถูก render สองครั้ง ทับกัน)
2. **รูปแบบอ่านยาก** — `2025-08` เป็นตัวเลขล้วน ควรเป็นชื่อเดือนไทย เช่น `ส.ค. 68`

## สิ่งที่ต้องแก้
เปิดไฟล์ widget กราฟแนวโน้มรายเดือน (น่าจะเป็น `LineChart` / `fl_chart` ในหน้า Dashboard — ค้นหาคำว่า "แนวโน้มการเข้าร่วมรายเดือน" ในโปรเจกต์)

### 1. ตัด label ซ้ำ
ปกติเกิดจากมีทั้ง `bottomTitles` **และ** label ที่วาดเองซ้อนกัน หรือ `interval` ไม่ได้ตั้งทำให้ทุกจุดโชว์ป้าย ให้:
- ตั้ง `SideTitles(showTitles: true, interval: <ระยะห่างที่เหมาะ>)` เพื่อไม่ให้ป้ายชนกัน
- ให้แต่ละ index แสดงป้าย **ครั้งเดียว** — คืน `SizedBox.shrink()` ถ้า index ไม่ตรง interval
- ลบโค้ดที่วาดป้ายเดือนซ้ำอีกชั้น (เช่น `Text` ใต้กราฟที่ loop เดือนซ้ำ)

### 2. ฟอร์แมตชื่อเดือนเป็นภาษาไทย
เพิ่ม helper:
```dart
String formatMonthLabel(DateTime d) {
  const months = ['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.',
                  'ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'];
  final yearShort = (d.year + 543) % 100; // พ.ศ. 2 หลัก
  return '${months[d.month - 1]} $yearShort';
}
```
ใช้ใน `getTitlesWidget`:
```dart
bottomTitles: AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    interval: 1,          // ปรับตามจำนวนจุด
    reservedSize: 32,
    getTitlesWidget: (value, meta) {
      final i = value.toInt();
      if (i < 0 || i >= data.length) return const SizedBox.shrink();
      // โชว์เว้นจุด ถ้าจุดเยอะ: if (i % 2 != 0) return const SizedBox.shrink();
      return SideTitleWidget(
        axisSide: meta.axisSide,
        space: 6,
        child: Text(
          formatMonthLabel(data[i].month),
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
      );
    },
  ),
),
```

### 3. กันป้ายชนกัน (ถ้าจุดเยอะ)
- หมุนป้ายเล็กน้อย: ครอบ `Text` ด้วย `Transform.rotate(angle: -0.5, ...)` หรือ
- แสดงเว้นจุด (`i % 2 != 0 → SizedBox.shrink()`)

## ผลลัพธ์ที่ควรได้
แกนล่างแสดง `ส.ค. 68  พ.ย. 68  ก.พ. 69  พ.ค. 69  ส.ค. 69` แบบไม่ซ้ำ ไม่ชนกัน อ่านง่าย

## หลังแก้เสร็จ หยุดให้ตรวจก่อน commit
