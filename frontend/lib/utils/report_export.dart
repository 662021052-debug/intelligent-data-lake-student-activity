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

/// ตัวกรองที่ส่งไปกับคำขอรายงาน — ตรงกับตัวกรองที่แสดงบนแดชบอร์ด (คณะ/ชั้นปี/ภาคเรียน)
///
/// **ภาคเรียนเปลี่ยนความหมายของ "ชั่วโมงที่ได้"**: นับเฉพาะชั่วโมงในภาคนั้น แต่ "ชั่วโมงที่
/// ต้องการ" ยังเป็นของทั้งหลักสูตร (ไฟล์ที่ได้เขียนบอกไว้ที่หัวรายงานแล้ว)
Map<String, String> reportQuery({String? faculty, int? yearLevel, int? semester}) => {
      'faculty': ?faculty,
      if (yearLevel != null) 'year_level': '$yearLevel',
      if (semester != null) 'semester': '$semester',
    };

/// รูปแบบของ PDF — Excel เป็นแบบละเอียดเสมอ (เอาไปกรอง/pivot ต่อได้)
enum ReportMode { summary, detail }

extension ReportModeInfo on ReportMode {
  /// ค่าที่ backend รับใน query `mode`
  String get apiValue => this == ReportMode.summary ? 'summary' : 'detail';

  String get label => this == ReportMode.summary ? 'สรุปต่อคน' : 'แบบละเอียด';

  String get description => this == ReportMode.summary
      ? '1 แถวต่อนิสิต 1 คน — ชั่วโมงรวม จำนวนหมวดที่ครบ และสถานะรวม'
      : '1 แถวต่อ 1 หมวดกิจกรรม — เห็นชั่วโมงที่ได้/ที่ต้องการของทุกหมวด';
}

/// query ของปุ่ม "ส่งออก PDF" = ตัวกรอง + รูปแบบ
Map<String, String> pdfReportQuery({
  String? faculty,
  int? yearLevel,
  int? semester,
  ReportMode mode = ReportMode.summary,
}) =>
    {...reportQuery(faculty: faculty, yearLevel: yearLevel, semester: semester), 'mode': mode.apiValue};

/// จำนวนแถว/หน้าโดยประมาณของแต่ละรูปแบบ (จาก `/reports/student-hours/count`)
/// ไว้เตือนผู้ใช้ก่อนออกไฟล์ใหญ่ โดยยังไม่ต้องสร้างไฟล์
class ReportCounts {
  const ReportCounts({
    required this.students,
    required this.summaryRows,
    required this.detailRows,
    required this.summaryPages,
    required this.detailPages,
    required this.largeThreshold,
  });

  factory ReportCounts.fromJson(Map<String, dynamic> json) => ReportCounts(
        students: json['students'] as int,
        summaryRows: json['summary_rows'] as int,
        detailRows: json['detail_rows'] as int,
        summaryPages: json['summary_pages'] as int,
        detailPages: json['detail_pages'] as int,
        largeThreshold: json['large_threshold'] as int,
      );

  final int students;
  final int summaryRows;
  final int detailRows;
  final int summaryPages;
  final int detailPages;
  final int largeThreshold;

  int rowsFor(ReportMode mode) => mode == ReportMode.summary ? summaryRows : detailRows;
  int pagesFor(ReportMode mode) => mode == ReportMode.summary ? summaryPages : detailPages;

  /// เกินเกณฑ์ (มากกว่า ไม่ใช่เท่ากับ) ที่ควรเตือนก่อนออกไฟล์
  bool isLarge(ReportMode mode) => rowsFor(mode) > largeThreshold;

  /// ข้อความเตือนของรูปแบบนั้น (null = ไม่ต้องเตือน)
  String? warningFor(ReportMode mode) {
    if (!isLarge(mode)) return null;
    final rows = _thousands(rowsFor(mode));
    final pages = _thousands(pagesFor(mode));
    return 'ไฟล์นี้จะมีประมาณ $rows แถว (ราว $pages หน้า) ใช้เวลาสร้างนานและไฟล์ใหญ่ '
        'แนะนำให้กรองคณะ/ชั้นปีก่อน'
        '${mode == ReportMode.detail ? ' หรือเลือกแบบสรุปต่อคน' : ''}';
  }

  static String _thousands(int n) => n.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ',',
      );
}

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
