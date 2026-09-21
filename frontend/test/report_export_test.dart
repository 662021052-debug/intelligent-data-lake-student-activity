import 'package:activity_tracking_frontend/utils/report_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// ตัวช่วยของปุ่ม "ส่งออก Excel/PDF" บนแดชบอร์ด (ข้อ 6.5)
void main() {
  group('ปลายทางของแต่ละรูปแบบ', () {
    test('path ตรงกับ endpoint ของ backend', () {
      expect(ReportFormat.xlsx.path, '/reports/student-hours.xlsx');
      expect(ReportFormat.pdf.path, '/reports/student-hours.pdf');
    });

    test('media type ตรงกับชนิดไฟล์ ไม่งั้นเบราว์เซอร์เปิดไฟล์ไม่ถูกโปรแกรม', () {
      expect(ReportFormat.xlsx.mediaType, contains('spreadsheetml'));
      expect(ReportFormat.pdf.mediaType, 'application/pdf');
    });

    test('ป้ายปุ่มเป็นภาษาไทยตามสเปก', () {
      expect(ReportFormat.xlsx.label, 'ส่งออก Excel');
      expect(ReportFormat.pdf.label, 'ส่งออก PDF');
    });
  });

  group('ชื่อไฟล์', () {
    test('เป็นภาษาไทยพร้อมวันที่ และนามสกุลถูกต้อง', () {
      final date = DateTime(2026, 8, 5);
      expect(reportFileName(ReportFormat.xlsx, date), 'รายงานชั่วโมงกิจกรรม_2026-08-05.xlsx');
      expect(reportFileName(ReportFormat.pdf, date), 'รายงานชั่วโมงกิจกรรม_2026-08-05.pdf');
    });

    test('เดือน/วันเลขเดียวเติมศูนย์หน้า ไฟล์จะได้เรียงตามวันที่ในโฟลเดอร์', () {
      expect(
        reportFileName(ReportFormat.pdf, DateTime(2026, 1, 9)),
        'รายงานชั่วโมงกิจกรรม_2026-01-09.pdf',
      );
    });
  });

  group('ตัวกรองที่ส่งไปกับคำขอ', () {
    test('ไม่เลือกอะไรเลย = ไม่ส่ง query param', () {
      expect(reportQuery(), isEmpty);
    });

    test('ส่งเฉพาะตัวที่เลือก', () {
      expect(reportQuery(faculty: 'วิทยาศาสตร์'), {'faculty': 'วิทยาศาสตร์'});
      expect(reportQuery(yearLevel: 4), {'year_level': '4'});
      expect(
        reportQuery(faculty: 'วิศวกรรมศาสตร์', yearLevel: 2),
        {'faculty': 'วิศวกรรมศาสตร์', 'year_level': '2'},
      );
    });

    test('ภาคเรียนส่งไปด้วย — ต้องตรงกับตัวกรองที่เห็นบนแดชบอร์ด', () {
      expect(reportQuery(semester: 2), {'semester': '2'});
      expect(
        reportQuery(faculty: 'วิทยาศาสตร์', yearLevel: 1, semester: 3),
        {'faculty': 'วิทยาศาสตร์', 'year_level': '1', 'semester': '3'},
      );
    });
  });

  group('รูปแบบ PDF (สรุปต่อคน / ละเอียด)', () {
    test('ค่าที่ส่งให้ backend ตรงกับ query `mode`', () {
      expect(ReportMode.summary.apiValue, 'summary');
      expect(ReportMode.detail.apiValue, 'detail');
    });

    test('query ของ PDF = ตัวกรอง + mode และค่าเริ่มต้นคือสรุปต่อคน', () {
      expect(pdfReportQuery(), {'mode': 'summary'});
      expect(
        pdfReportQuery(faculty: 'คณะนิติศาสตร์', yearLevel: 2, semester: 1, mode: ReportMode.detail),
        {'faculty': 'คณะนิติศาสตร์', 'year_level': '2', 'semester': '1', 'mode': 'detail'},
      );
    });
  });

  group('เตือนก่อนออกไฟล์ใหญ่', () {
    ReportCounts counts({int students = 4078, int detail = 20390}) => ReportCounts(
          students: students,
          summaryRows: students,
          detailRows: detail,
          summaryPages: (students / 24).ceil(),
          detailPages: (detail / 24).ceil(),
          largeThreshold: 5000,
        );

    test('อ่านจาก JSON ของ /reports/student-hours/count', () {
      final c = ReportCounts.fromJson({
        'students': 2,
        'summary_rows': 2,
        'detail_rows': 4,
        'summary_pages': 1,
        'detail_pages': 1,
        'large_threshold': 5000,
      });
      expect(c.rowsFor(ReportMode.summary), 2);
      expect(c.rowsFor(ReportMode.detail), 4);
      expect(c.largeThreshold, 5000);
    });

    test('ทั้งมหาวิทยาลัย: แบบละเอียดเตือน แบบสรุปไม่เตือน', () {
      final c = counts();
      expect(c.isLarge(ReportMode.summary), isFalse); // 4,078 คน ≤ 5,000
      expect(c.warningFor(ReportMode.summary), isNull);
      expect(c.isLarge(ReportMode.detail), isTrue); // 20,390 แถว
      final warning = c.warningFor(ReportMode.detail)!;
      expect(warning, contains('20,390'));
      expect(warning, contains('กรอง'));
      expect(warning, contains('สรุปต่อคน')); // แนะนำทางออกที่เล็กกว่า
    });

    test('เกณฑ์คือ "มากกว่า" 5,000 — เท่ากับพอดีไม่เตือน', () {
      expect(counts(students: 5000, detail: 5000).isLarge(ReportMode.detail), isFalse);
      expect(counts(students: 5001, detail: 5001).isLarge(ReportMode.detail), isTrue);
    });

    test('แบบสรุปที่ใหญ่เกินก็เตือน แต่ไม่แนะนำ "เลือกสรุปต่อคน" ซ้ำ', () {
      final warning = counts(students: 6000, detail: 30000).warningFor(ReportMode.summary)!;
      expect(warning, contains('6,000'));
      expect(warning, isNot(contains('สรุปต่อคน')));
    });
  });

  group('ดาวน์โหลด Bronze / Silver (admin)', () {
    test('path ตรงกับ endpoint ของ backend', () {
      expect(LakeLayer.bronze.path, '/export/bronze.zip');
      expect(LakeLayer.silver.path, '/export/silver.csv');
    });

    test('ป้ายปุ่มเป็นภาษาไทยตามสเปก', () {
      expect(LakeLayer.bronze.label, 'ส่งออก Bronze (ZIP)');
      expect(LakeLayer.silver.label, 'ส่งออก Silver (CSV)');
    });

    test('media type ตรงกับชนิดไฟล์', () {
      expect(LakeLayer.bronze.mediaType, 'application/zip');
      expect(LakeLayer.silver.mediaType, 'text/csv');
    });

    test('ชื่อไฟล์มีวันที่และนามสกุลถูกต้อง เดือน/วันเลขเดียวเติมศูนย์', () {
      final date = DateTime(2026, 1, 9);
      expect(lakeFileName(LakeLayer.bronze, date), 'bronze_evidence_2026-01-09.zip');
      expect(lakeFileName(LakeLayer.silver, date), 'silver_evidence_ocr_2026-01-09.csv');
    });
  });
}
