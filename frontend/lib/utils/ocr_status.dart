/// Short badge label for an OCR decision (Silver layer).
/// สีของแต่ละสถานะอยู่ที่ `widgets/status_chip.dart` ที่เดียว
String ocrDecisionLabel(String decision) {
  switch (decision) {
    case 'auto_approved':
      return '✅ ระบบอนุมัติอัตโนมัติ';
    case 'flagged':
      return '⚠️ ไฟล์ซ้ำ';
    case 'needs_review':
    default:
      return '👁️ รอเจ้าหน้าที่ตรวจ';
  }
}

/// Renders a value in 0–1 as a whole-number percentage string, e.g. 0.83 -> "83%".
String asPercent(double value) => '${(value * 100).round()}%';
