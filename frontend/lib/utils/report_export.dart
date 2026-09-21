/// ตัวช่วยของการส่งออกรายงานชั่วโมง (ข้อ 6.5)
///
/// แยกเป็นฟังก์ชันบริสุทธิ์เพื่อให้เทสต์ยืนยัน path/ชื่อไฟล์/ตัวกรองได้ โดยไม่ต้อง
/// เปิดหน้าแดชบอร์ดจริง (ซึ่งต้องยิง API หลายเส้น)
library;

/// รูปแบบไฟล์ที่ backend ส่งออกได้
enum ReportFormat { xlsx, pdf }

extension ReportFormatInfo on ReportFormat {
  String get extension => this == ReportFormat.xlsx ? 'xlsx' : 'pdf';

  /// ชื่อรูปแบบไฟล์ที่ผู้ใช้เห็น
  String get displayName => this == ReportFormat.xlsx ? 'Excel' : 'PDF';

  String get label => 'ส่งออก $displayName';

  String get mediaType => this == ReportFormat.xlsx
      ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      : 'application/pdf';

  String get path => '/reports/student-hours.$extension';
}

/// ชื่อไฟล์ภาษาไทยพร้อมวันที่ — ต้องตรงกับที่ backend ตั้งใน Content-Disposition
/// เพราะฝั่งเว็บสร้างไฟล์จาก blob เอง จึงตั้งชื่อเองด้วย
String reportFileName(ReportFormat format, [DateTime? now]) {
  final date = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${date.year}-${two(date.month)}-${two(date.day)}';
  return 'รายงานชั่วโมงกิจกรรม_$stamp.${format.extension}';
}

/// ตัวกรองที่ส่งไปกับคำขอรายงาน
///
/// **ภาคเรียนไม่ถูกส่งไปด้วยโดยตั้งใจ** — `gold_student_hours` เป็นยอดสะสมทั้งหลักสูตร
/// ไม่ได้แบ่งตามภาคเรียน ถ้าแอบส่งไปแล้ว backend เมิน ผู้ใช้จะเข้าใจผิดว่าไฟล์ที่ได้
/// กรองภาคเรียนมาแล้ว
Map<String, String> reportQuery({String? faculty, int? yearLevel}) => {
      'faculty': ?faculty,
      if (yearLevel != null) 'year_level': '$yearLevel',
    };

/// ดาวน์โหลดข้อมูลดิบของ Data Lake (เฉพาะ admin) — ต่างจาก [ReportFormat] ที่เป็นรายงานสรุปจาก Gold
///
/// ไม่มีตัวกรองคณะ/ชั้นปี/ภาคเรียน: endpoint ฝั่ง backend กรองได้แค่ activity/student/ช่วงวันที่
/// ปุ่มบนแดชบอร์ดจึงส่งออก "ทั้งหมด" เสมอ (บอกไว้ใน tooltip ไม่ให้เข้าใจว่ากรองตามหน้าจอ)
enum LakeLayer { bronze, silver }

extension LakeLayerInfo on LakeLayer {
  String get extension => this == LakeLayer.bronze ? 'zip' : 'csv';

  String get label => this == LakeLayer.bronze ? 'ส่งออก Bronze (ZIP)' : 'ส่งออก Silver (CSV)';

  String get displayName => this == LakeLayer.bronze ? 'Bronze' : 'Silver';

  String get mediaType => this == LakeLayer.bronze ? 'application/zip' : 'text/csv';

  String get path => this == LakeLayer.bronze ? '/export/bronze.zip' : '/export/silver.csv';
}

/// ชื่อไฟล์พร้อมวันที่ — ฝั่งเว็บสร้างไฟล์จาก blob เอง จึงตั้งชื่อเองเหมือน [reportFileName]
String lakeFileName(LakeLayer layer, [DateTime? now]) {
  final date = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${date.year}-${two(date.month)}-${two(date.day)}';
  final base = layer == LakeLayer.bronze ? 'bronze_evidence' : 'silver_evidence_ocr';
  return '${base}_$stamp.${layer.extension}';
}
