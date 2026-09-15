import '../models/ocr_result.dart';

/// Short badge label for an OCR decision (Silver layer).
/// สีของแต่ละสถานะอยู่ที่ `widgets/status_chip.dart` ที่เดียว
///
/// ใบ flagged บอกเหตุผลที่ซ้ำด้วย ([duplicateReason]) — ป้าย "ไฟล์ซ้ำ" ลอย ๆ ทำให้
/// เจ้าหน้าที่แยกไม่ออกว่าน่าสงสัยแค่ไหน
String ocrDecisionLabel(String decision, {String? duplicateReason}) {
  switch (decision) {
    case 'auto_approved':
      return '✅ ระบบอนุมัติอัตโนมัติ';
    case 'flagged':
      return duplicateReasonLabel(duplicateReason);
    case 'needs_review':
    default:
      return '👁️ รอเจ้าหน้าที่ตรวจ';
  }
}

/// ป้ายสั้นของไฟล์ซ้ำตามเหตุผล — null = ผล OCR ก่อนเฟส 1.2 ที่ยังไม่มีรายละเอียด
String duplicateReasonLabel(String? reason) => switch (reason) {
      'cross_student' => '⚠️ ซ้ำกับนิสิตคนอื่น',
      'same_student_reuse' => '⚠️ ใช้ไฟล์เดิมซ้ำ',
      'matches_rejected' => '⚠️ ตรงกับใบที่เคยถูกปฏิเสธ',
      _ => '⚠️ ไฟล์ซ้ำ',
    };

/// ซ้ำแบบรุนแรง (แดง) หรือเป็นสัญญาณให้ดูเพิ่ม (เหลือง)
///
/// แดง: ซ้ำกับใบของนิสิตคนอื่น · ตรงกับใบที่เคยถูกปฏิเสธ (เอาไฟล์ที่ไม่ผ่านมาส่งใหม่)
/// · ผลรุ่นเก่าที่ไม่รู้เหตุผลนับเป็นรุนแรงไว้ก่อน (เหมือนป้ายเดิม)
/// เหลือง: คนเดิมใช้ไฟล์เดิมกับการเข้าร่วมอื่นเท่านั้น
bool isSevereDuplicate(String? reason) => reason != 'same_student_reuse';

/// ข้อความเต็มว่าซ้ำกับใบไหน — ใช้ทั้งแถบในหน้าตรวจและ dialog ยืนยันการอนุมัติ
String duplicateContextMessage(OcrResult ocr) {
  final who = _studentLabel(ocr.duplicateOfStudentName, ocr.duplicateOfStudentCode) ?? 'ไม่ทราบชื่อ';
  final activity = ocr.duplicateOfActivityName;
  final activityPart = activity == null ? '' : ' · กิจกรรม $activity';
  return switch (ocr.duplicateReason) {
    'cross_student' => '⚠ ซ้ำกับใบของนิสิตคนอื่น: $who$activityPart',
    'same_student_reuse' => activity == null
        ? 'ใช้ไฟล์เดิมกับการเข้าร่วมอื่นของนิสิตคนนี้'
        : 'ใช้ไฟล์เดิมกับกิจกรรม $activity',
    'matches_rejected' => 'ตรงกับใบที่เคยถูกปฏิเสธ: $who$activityPart',
    _ => 'ไฟล์นี้ซ้ำกับใบอื่นในระบบ — ผลตรวจรุ่นเก่ายังไม่มีรายละเอียด '
        'กด "ประมวลผล OCR" เพื่อตรวจใหม่',
  };
}

String? _studentLabel(String? name, String? code) {
  if (name == null) return code;
  return code == null ? name : '$name ($code)';
}

/// Renders a value in 0–1 as a whole-number percentage string, e.g. 0.83 -> "83%".
String asPercent(double value) => '${(value * 100).round()}%';
