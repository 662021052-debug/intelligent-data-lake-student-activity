import 'package:activity_tracking_frontend/utils/report_export.dart';
import 'package:activity_tracking_frontend/widgets/report_pdf_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dialog เลือกรูปแบบก่อนส่งออก PDF (สรุปต่อคน / ละเอียด) + คำเตือนไฟล์ใหญ่
void main() {
  const universityWide = ReportCounts(
    students: 4078,
    summaryRows: 4078,
    detailRows: 20390,
    summaryPages: 170,
    detailPages: 850,
    largeThreshold: 5000,
  );

  /// เปิด dialog จากปุ่ม — ผลที่ dialog ปิดพร้อมส่งกลับถูกส่งเข้า [picked]
  Future<void> open(
    WidgetTester tester, {
    ReportCounts? counts,
    required void Function(ReportMode?) picked,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => picked(await showReportPdfDialog(
                context,
                filterSummary: 'ทุกคณะ • ทุกชั้นปี • ทุกภาคเรียน',
                counts: counts,
              )),
              child: const Text('เปิด'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
  }

  testWidgets('ค่าเริ่มต้นคือ "สรุปต่อคน" และกดดาวน์โหลดได้ค่านั้น', (tester) async {
    ReportMode? result;
    await open(tester, picked: (m) => result = m);

    expect(find.text('สรุปต่อคน (แนะนำ)'), findsOneWidget);
    expect(find.text('แบบละเอียด'), findsOneWidget);
    expect(find.textContaining('ทุกคณะ • ทุกชั้นปี'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-confirm')));
    await tester.pumpAndSettle();
    expect(result, ReportMode.summary);
  });

  testWidgets('เลือกแบบละเอียดแล้วได้ค่า detail', (tester) async {
    ReportMode? result;
    await open(tester, picked: (m) => result = m);

    await tester.tap(find.byKey(const ValueKey('report-mode-detail')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('report-confirm')));
    await tester.pumpAndSettle();
    expect(result, ReportMode.detail);
  });

  testWidgets('ยกเลิก = null (ไม่ออกไฟล์)', (tester) async {
    ReportMode? result = ReportMode.detail;
    await open(tester, picked: (m) => result = m);

    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('ทั้งมหาวิทยาลัย: โชว์จำนวนแถว/หน้า และเตือนเฉพาะตอนเลือกแบบละเอียด', (tester) async {
    await open(tester, counts: universityWide, picked: (_) {});

    expect(find.textContaining('4078 แถว · ประมาณ 170 หน้า'), findsOneWidget);
    expect(find.textContaining('20390 แถว · ประมาณ 850 หน้า'), findsOneWidget);
    // ค่าเริ่มต้น = สรุปต่อคน (4,078 ≤ 5,000) → ยังไม่เตือน
    expect(find.byKey(const ValueKey('report-large-warning')), findsNothing);
    expect(find.text('ดาวน์โหลด'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-mode-detail')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-large-warning')), findsOneWidget);
    expect(find.textContaining('20,390 แถว'), findsOneWidget);
    expect(find.text('ดาวน์โหลดต่อ'), findsOneWidget); // ปุ่มบอกว่ารับรู้คำเตือนแล้ว
  });

  testWidgets('ดึงจำนวนไม่ได้ (counts = null) ก็ยังเลือกและออกไฟล์ได้ ไม่มีคำเตือน', (tester) async {
    ReportMode? result;
    await open(tester, counts: null, picked: (m) => result = m);

    expect(find.textContaining('แถว · ประมาณ'), findsNothing);
    expect(find.byKey(const ValueKey('report-large-warning')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('report-confirm')));
    await tester.pumpAndSettle();
    expect(result, ReportMode.summary);
  });
}
