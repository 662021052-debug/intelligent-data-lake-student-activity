import 'package:flutter/material.dart';

/// Short badge label for an OCR decision (Silver layer).
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

Color ocrDecisionColor(String decision) {
  switch (decision) {
    case 'auto_approved':
      return Colors.green.shade100;
    case 'flagged':
      return Colors.orange.shade100;
    case 'needs_review':
    default:
      return Colors.blueGrey.shade100;
  }
}

/// Renders a value in 0–1 as a whole-number percentage string, e.g. 0.83 -> "83%".
String asPercent(double value) => '${(value * 100).round()}%';
