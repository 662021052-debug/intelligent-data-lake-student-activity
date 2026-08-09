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

    test('ไม่มี semester ติดไปด้วย — รายงานเป็นยอดสะสม ไม่ได้แบ่งตามภาคเรียน', () {
      expect(reportQuery(faculty: 'วิทยาศาสตร์', yearLevel: 1).keys, isNot(contains('semester')));
    });
  });
}
