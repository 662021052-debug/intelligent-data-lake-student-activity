/// แสดงชั่วโมงเป็นจำนวนเต็มเมื่อไม่มีเศษ (เช่น 4.0 → "4")
String formatHours(double hours) =>
    hours == hours.roundToDouble() ? hours.toInt().toString() : hours.toString();
