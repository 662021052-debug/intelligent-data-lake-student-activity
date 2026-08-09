/// แสดงชั่วโมงเป็นจำนวนเต็มเมื่อไม่มีเศษ (เช่น 4.0 → "4")
String formatHours(double hours) =>
    hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toString();

/// แปลงเวลาที่ backend บันทึกไว้ (UTC แบบไม่มี timezone จาก `datetime.utcnow()`)
/// ให้เป็นเวลาท้องถิ่นของเครื่อง
///
/// สตริงที่ไม่มีโซนเวลาจะถูก `DateTime.parse` อ่านเป็น "เวลาท้องถิ่น" ตามตัวอักษร
/// ทั้งที่ค่าจริงเป็น UTC — ถ้าไม่แปลงจะเพี้ยนไป 7 ชม. ในไทย ซึ่งเห็นชัดมากกับ
/// เวลาเช็กอินที่เพิ่งเกิดขึ้นสด ๆ หน้างาน
DateTime serverTimeToLocal(DateTime value) {
  if (value.isUtc) return value.toLocal();
  return DateTime.utc(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
  ).toLocal();
}

/// เวลาแบบสั้นสำหรับแสดงผล: `2026-08-02 17:05`
String formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

const _thaiMonthsShort = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

/// ป้ายเดือนสำหรับแกนกราฟ: ค.ศ. 2025 เดือน 8 → `ส.ค. 68`
///
/// ปีเป็น พ.ศ. สองหลักเพื่อให้ป้ายสั้นพอที่จะวางเรียงกันบนแกนได้โดยไม่ชนกัน
String formatMonthLabel(DateTime d) {
  final yearShort = ((d.year + 543) % 100).toString().padLeft(2, '0');
  return '${_thaiMonthsShort[d.month - 1]} $yearShort';
}
