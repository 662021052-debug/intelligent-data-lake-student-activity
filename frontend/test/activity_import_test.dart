import 'package:activity_tracking_frontend/models/activity_import.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/screens/activity_import_dialog.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/activity_import_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ธีมจริงตั้ง splashFactory เป็น InkRipple ส่วนดีฟอลต์ M3 เป็น InkSparkle ที่ต้อง
// โหลด shader asset ซึ่งไม่มีตอนรัน --no-test-assets
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

ActivityImportResult _result({
  int total = 3,
  List<ActivityImportCreated> created = const [],
  List<ActivityImportRowError> errors = const [],
}) =>
    ActivityImportResult(
      totalRows: total,
      createdCount: created.length,
      errorCount: errors.length,
      created: created,
      errors: errors,
    );

void main() {
  group('แปลงผลลัพธ์จาก backend', () {
    test('อ่านครบทุกฟิลด์ รวมทั้งเลขแถวของแถวที่ผิด', () {
      final result = ActivityImportResult.fromJson({
        'total_rows': 3,
        'created_count': 2,
        'error_count': 1,
        'created': [
          {'row': 2, 'id': 11, 'name': 'อบรมการใช้ห้องสมุด'},
          {'row': 3, 'id': 12, 'name': 'ค่ายอาสา'},
        ],
        'errors': [
          {'row': 4, 'message': 'วันเวลากิจกรรมเป็นอดีต'},
        ],
      });

      expect(result.totalRows, 3);
      expect(result.created.first.name, 'อบรมการใช้ห้องสมุด');
      expect(result.errors.single.row, 4);
      expect(result.isPartial, isTrue);
      expect(result.isCompleteFailure, isFalse);
    });

    test('ไม่มีแถวไหนสำเร็จเลย = ล้มทั้งไฟล์', () {
      final result = _result(
        errors: [ActivityImportRowError(row: 2, message: 'ไม่พบหมวดย่อย')],
      );
      expect(result.isCompleteFailure, isTrue);
      expect(result.isPartial, isFalse);
    });
  });

  group('สรุปผลการนำเข้า', () {
    testWidgets('สำเร็จทั้งหมด: บอกจำนวนแถว และเตือนว่ายังต้องรออนุมัติ', (tester) async {
      await tester.pumpWidget(_wrap(ActivityImportSummary(
        result: _result(
          total: 2,
          created: [
            ActivityImportCreated(row: 2, id: 1, name: 'ก'),
            ActivityImportCreated(row: 3, id: 2, name: 'ข'),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('เพิ่มสำเร็จ 2 แถว'), findsOneWidget);
      expect(find.textContaining('ผิด 0 แถว'), findsOneWidget);
      expect(find.textContaining('รออนุมัติ'), findsOneWidget);
      expect(find.text('แถวที่ต้องกลับไปแก้'), findsNothing);
    });

    testWidgets('ผู้นำเข้าเป็น admin: กิจกรรมอนุมัติแล้ว จึงไม่ต้องเตือนให้ไปอนุมัติ',
        (tester) async {
      await tester.pumpWidget(_wrap(ActivityImportSummary(
        needsApproval: false,
        result: _result(
          total: 1,
          created: [ActivityImportCreated(row: 2, id: 1, name: 'ก')],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('เพิ่มสำเร็จ 1 แถว'), findsOneWidget);
      expect(find.textContaining('รออนุมัติ'), findsNothing);
    });

    testWidgets('สำเร็จบางส่วน: ต้องเห็นทั้งจำนวนที่สำเร็จและเลขแถวที่ผิด', (tester) async {
      await tester.pumpWidget(_wrap(ActivityImportSummary(
        result: _result(
          total: 3,
          created: [ActivityImportCreated(row: 2, id: 1, name: 'ก')],
          errors: [
            ActivityImportRowError(row: 3, message: 'วันเวลากิจกรรมเป็นอดีต'),
            ActivityImportRowError(row: 4, message: 'ไม่พบหมวดย่อย "หมวดมั่ว" ในระบบ'),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('เพิ่มสำเร็จ 1 แถว'), findsOneWidget);
      expect(find.text('แถวที่ต้องกลับไปแก้'), findsOneWidget);
      expect(find.text('แถว 3'), findsOneWidget);
      expect(find.text('วันเวลากิจกรรมเป็นอดีต'), findsOneWidget);
      expect(find.text('แถว 4'), findsOneWidget);
    });

    testWidgets('ไม่ผ่านเลย: ไม่ต้องขึ้นข้อความรออนุมัติ', (tester) async {
      await tester.pumpWidget(_wrap(ActivityImportSummary(
        result: _result(
          total: 1,
          errors: [ActivityImportRowError(row: 2, message: 'ชั่วโมงต้องมากกว่า 0')],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('รออนุมัติ'), findsNothing);
      expect(find.text('ชั่วโมงต้องมากกว่า 0'), findsOneWidget);
    });
  });

  group('dialog นำเข้าแผนกิจกรรม', () {
    testWidgets('มีทั้งปุ่มดาวน์โหลดไฟล์ต้นแบบและปุ่มเลือกไฟล์ พร้อมบอกคอลัมน์ที่ต้องมี',
        (tester) async {
      await tester.pumpWidget(_wrap(const ActivityImportDialog()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'ดาวน์โหลดไฟล์ต้นแบบ'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'เลือกไฟล์และนำเข้า'), findsOneWidget);
      expect(find.textContaining('หมวดย่อย'), findsOneWidget);
      expect(find.textContaining('ไม่ล้มทั้งไฟล์'), findsOneWidget);
    });

    testWidgets('กดเลือกไฟล์บนแพลตฟอร์มที่เลือกไฟล์ไม่ได้ ต้องไม่ค้างและไม่ขึ้น error',
        (tester) async {
      // บน VM ตัวเลือกไฟล์คืน null (stub) — ถือเป็น "ผู้ใช้กดยกเลิก" ไม่ใช่ข้อผิดพลาด
      await tester.pumpWidget(_wrap(const ActivityImportDialog()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'เลือกไฟล์และนำเข้า'));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('ไฟล์:'), findsNothing);
    });
  });

  group('ปุ่มนำเข้าบนหน้าจัดการกิจกรรม', () {
    tearDown(() => authService.logout());

    testWidgets('นิสิตไม่เห็นปุ่มนำเข้า', (tester) async {
      authService.token = 'fake-token';
      authService.username = '650811001';
      authService.role = 'student';

      await tester.pumpWidget(const MaterialApp(home: ActivitiesScreen()));
      await tester.pump();

      expect(find.text('นำเข้าแผนกิจกรรม'), findsNothing);
    });

    for (final role in ['staff', 'admin']) {
      testWidgets('$role เห็นปุ่มนำเข้า', (tester) async {
        authService.token = 'fake-token';
        authService.username = role;
        authService.role = role;

        await tester.pumpWidget(const MaterialApp(home: ActivitiesScreen()));
        await tester.pump();

        expect(find.text('นำเข้าแผนกิจกรรม'), findsOneWidget);
      });
    }
  });
}
