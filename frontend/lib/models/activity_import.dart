/// ผลการนำเข้าแผนกิจกรรมจากไฟล์ Excel/CSV (ข้อ 6.7)
///
/// backend ตั้งใจตอบ 200 แม้บางแถวจะผิด — ไฟล์หนึ่งไฟล์ไม่ล้มทั้งไฟล์เพราะแถวเดียว
/// พิมพ์ผิด หน้าจอจึงต้องแสดง "สำเร็จกี่แถว ผิดกี่แถว" คู่กันเสมอ ไม่ใช่แค่สำเร็จ/ล้มเหลว
class ActivityImportResult {
  final int totalRows;
  final int createdCount;
  final int errorCount;
  final List<ActivityImportCreated> created;
  final List<ActivityImportRowError> errors;

  ActivityImportResult({
    required this.totalRows,
    required this.createdCount,
    required this.errorCount,
    required this.created,
    required this.errors,
  });

  /// ไม่มีแถวไหนถูกสร้างเลย — ใช้เลือกสีและข้อความหัวสรุป
  bool get isCompleteFailure => createdCount == 0;

  /// สร้างได้บางส่วน แต่ยังมีแถวที่ต้องกลับไปแก้
  bool get isPartial => createdCount > 0 && errorCount > 0;

  factory ActivityImportResult.fromJson(Map<String, dynamic> json) => ActivityImportResult(
        totalRows: json['total_rows'] as int,
        createdCount: json['created_count'] as int,
        errorCount: json['error_count'] as int,
        created: (json['created'] as List)
            .map((e) => ActivityImportCreated.fromJson(e as Map<String, dynamic>))
            .toList(),
        errors: (json['errors'] as List)
            .map((e) => ActivityImportRowError.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ActivityImportCreated {
  final int row;
  final int id;
  final String name;

  ActivityImportCreated({required this.row, required this.id, required this.name});

  factory ActivityImportCreated.fromJson(Map<String, dynamic> json) => ActivityImportCreated(
        row: json['row'] as int,
        id: json['id'] as int,
        name: json['name'] as String,
      );
}

class ActivityImportRowError {
  /// เลขแถวจริงในไฟล์ (หัวตาราง = แถว 1) เพื่อให้ผู้ใช้เปิดไฟล์ไปแก้ถูกบรรทัด
  final int row;
  final String message;

  ActivityImportRowError({required this.row, required this.message});

  factory ActivityImportRowError.fromJson(Map<String, dynamic> json) => ActivityImportRowError(
        row: json['row'] as int,
        message: json['message'] as String,
      );
}
