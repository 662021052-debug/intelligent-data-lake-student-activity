/// แปลง error จาก API ให้เป็นข้อความไทยที่ผู้ใช้อ่านรู้เรื่อง
///
/// เดิมแต่ละหน้าเอา `e.toString()` มาโชว์ตรง ๆ ทำให้ผู้ใช้เห็น JSON ดิบของ
/// Pydantic เช่น `[{type: less_than_equal, loc: [query, limit], ...}]` ซึ่งไม่มีทาง
/// เข้าใจได้ ทุกหน้าจึงควรเรียกผ่านตัวกลางในไฟล์นี้ที่เดียว
library;

/// ป้ายชื่อฟิลด์ (ภาษาไทย) สำหรับ `loc` ที่ Pydantic ส่งกลับมา
const Map<String, String> _fieldLabels = {
  // auth / users
  'username': 'ชื่อผู้ใช้',
  'password': 'รหัสผ่าน',
  'role': 'สิทธิ์การใช้งาน',
  'student_id': 'นิสิตที่ผูกบัญชี',
  // students
  'full_name': 'ชื่อ-สกุล',
  'faculty': 'คณะ',
  'major': 'สาขา',
  'year_level': 'ชั้นปี',
  'status': 'สถานะ',
  // activities
  'name': 'ชื่อกิจกรรม',
  'activity_type': 'ประเภทกิจกรรม',
  'subcategory_id': 'หมวดชั่วโมง',
  'hours': 'จำนวนชั่วโมง',
  'start_at': 'วันเวลาเริ่ม',
  'end_at': 'วันเวลาสิ้นสุด',
  'location': 'สถานที่',
  'max_participants': 'จำนวนผู้เข้าร่วมสูงสุด',
  // participations
  'activity_id': 'กิจกรรม',
  'evidence_status': 'สถานะหลักฐาน',
  'hours_earned': 'ชั่วโมงที่ได้รับ',
  // query params
  'skip': 'ลำดับเริ่มต้น',
  'limit': 'จำนวนต่อหน้า',
  'search': 'คำค้นหา',
  'semester': 'ภาคเรียน',
  'threshold': 'เกณฑ์',
  'question': 'คำถาม',
};

String _fieldLabel(List<dynamic> loc) {
  // loc = ["body", "hours"] หรือ ["query", "limit"] — เอาชิ้นสุดท้ายที่เป็นชื่อฟิลด์
  for (final part in loc.reversed) {
    if (part is String && part != 'body' && part != 'query' && part != 'path') {
      return _fieldLabels[part] ?? part;
    }
  }
  return 'ข้อมูล';
}

/// อธิบายสาเหตุจาก `type` ของ Pydantic v2 เป็นภาษาไทย
String _reason(Map<String, dynamic> error) {
  final type = (error['type'] ?? '').toString();
  final ctx = error['ctx'] is Map ? error['ctx'] as Map : const {};

  switch (type) {
    case 'missing':
      return 'ต้องระบุ';
    case 'extra_forbidden':
      return 'ไม่อนุญาตให้ส่งค่านี้';
    case 'less_than_equal':
      return 'ต้องไม่เกิน ${ctx['le']}';
    case 'less_than':
      return 'ต้องน้อยกว่า ${ctx['lt']}';
    case 'greater_than_equal':
      return 'ต้องไม่น้อยกว่า ${ctx['ge']}';
    case 'greater_than':
      return 'ต้องมากกว่า ${ctx['gt']}';
    case 'string_too_short':
      return 'ต้องยาวอย่างน้อย ${ctx['min_length']} ตัวอักษร';
    case 'string_too_long':
      return 'ต้องยาวไม่เกิน ${ctx['max_length']} ตัวอักษร';
    case 'int_parsing':
    case 'int_type':
    case 'float_parsing':
    case 'decimal_parsing':
      return 'ต้องเป็นตัวเลข';
    case 'datetime_parsing':
    case 'datetime_type':
      return 'รูปแบบวันเวลาไม่ถูกต้อง';
    case 'enum':
      return 'ค่าที่เลือกไม่ถูกต้อง';
    case 'json_invalid':
      return 'รูปแบบข้อมูลไม่ถูกต้อง';
    default:
      // value_error ฯลฯ — ข้อความจาก backend มักอ่านได้อยู่แล้ว
      final msg = (error['msg'] ?? '').toString();
      return msg.isEmpty ? 'ข้อมูลไม่ถูกต้อง' : msg.replaceFirst('Value error, ', '');
  }
}

/// ข้อความสำรองตามรหัสสถานะ เมื่อ backend ไม่ได้ส่ง `detail` ที่อ่านได้มา
String _statusMessage(int statusCode) {
  switch (statusCode) {
    case 400:
      return 'ข้อมูลที่ส่งไม่ถูกต้อง';
    case 401:
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    case 403:
      return 'คุณไม่มีสิทธิ์ทำรายการนี้';
    case 404:
      return 'ไม่พบข้อมูลที่ต้องการ';
    case 409:
      return 'ข้อมูลซ้ำกับที่มีอยู่แล้ว';
    case 413:
      return 'ไฟล์มีขนาดใหญ่เกินกำหนด';
    case 422:
      return 'ข้อมูลที่กรอกไม่ถูกต้อง';
    case 500:
      return 'เซิร์ฟเวอร์ขัดข้อง กรุณาลองใหม่อีกครั้ง';
    case 503:
      return 'ระบบไม่พร้อมให้บริการชั่วคราว';
    default:
      return 'เกิดข้อผิดพลาด ($statusCode)';
  }
}

/// สร้างข้อความไทยจาก response ที่ไม่สำเร็จ — ใช้ใน `ApiService` ที่เดียว
///
/// [body] คือ body ที่ decode แล้ว (หรือ null ถ้า decode ไม่ได้)
String apiErrorMessage(int statusCode, Object? body) {
  final detail = body is Map ? body['detail'] : null;

  // 400/403/404 ฯลฯ ที่ backend เขียนข้อความไทยมาให้แล้ว — ใช้ตามนั้น
  if (detail is String && detail.trim().isNotEmpty) {
    return detail;
  }

  // 422 ของ FastAPI: detail เป็น list ของ validation error
  if (detail is List && detail.isNotEmpty) {
    final parts = <String>[];
    for (final item in detail) {
      if (item is! Map) continue;
      final error = item.cast<String, dynamic>();
      final loc = error['loc'] is List ? error['loc'] as List : const [];
      parts.add('${_fieldLabel(loc)}: ${_reason(error)}');
    }
    if (parts.isNotEmpty) {
      return '${_statusMessage(statusCode)} (${parts.join(', ')})';
    }
  }

  return _statusMessage(statusCode);
}

/// แปลง exception ใด ๆ ที่หน้าจอจับได้ ให้เป็นข้อความพร้อมแสดงผล
///
/// - `ApiException` มีข้อความไทยจาก [apiErrorMessage] อยู่แล้ว
/// - error เครือข่าย (ต่อ backend ไม่ติด) แปลงเป็นข้อความที่บอกทางแก้
String friendlyError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  final lower = text.toLowerCase();
  if (lower.contains('clientexception') ||
      lower.contains('socketexception') ||
      lower.contains('failed to fetch') ||
      lower.contains('connection refused') ||
      lower.contains('xmlhttprequest')) {
    return 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบว่าเปิด backend อยู่หรือไม่';
  }
  if (lower.contains('timeout')) {
    return 'เซิร์ฟเวอร์ตอบสนองช้าเกินไป กรุณาลองใหม่';
  }
  return text;
}
