import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// หน้าจัดการนิสิตยิง API ตอนเปิด ซึ่งในเทสต์ล้มเหลว — ที่ตรวจคือ "แถบตัวกรอง"
/// ซึ่งวาดได้โดยไม่ต้องรอข้อมูล (รายชื่อคณะจริงถูกครอบไว้ใน student_form_test)
Widget _app() => MaterialApp(theme: AppTheme.light, home: const StudentsScreen());

void _wideScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void _loginAsAdmin() {
  authService.token = 'fake-token';
  authService.username = 'admin';
  authService.role = 'admin';
}

/// ค่าที่ตัวกรองชั้นปีถืออยู่ (null = ทุกชั้นปี)
int? _yearFilterValue(WidgetTester tester) =>
    tester.widget<DropdownButton<int?>>(find.byType(DropdownButton<int?>)).value;

Future<void> _openStudentsPage(WidgetTester tester) async {
  _wideScreen(tester);
  _loginAsAdmin();
  await tester.pumpWidget(_app());
  await tester.pump();
}

void main() {
  tearDown(() => authService.logout());

  group('ตัวกรองในหน้าจัดการนิสิต', () {
    testWidgets('มีตัวกรองคณะ/ชั้นปี/สถานะ อยู่ข้างช่องค้นหา', (tester) async {
      await _openStudentsPage(tester);

      expect(find.text('ค้นหาชื่อ/รหัสนิสิต'), findsOneWidget);
      expect(find.text('ทุกคณะ'), findsOneWidget);
      expect(find.text('ทุกชั้นปี'), findsOneWidget);
      expect(find.text('สถานะทั้งหมด'), findsOneWidget);
    });

    testWidgets('ตัวกรองชั้นปีมีให้เลือก 1-4', (tester) async {
      await _openStudentsPage(tester);

      await tester.tap(find.text('ทุกชั้นปี'));
      await tester.pumpAndSettle();

      for (final year in [1, 2, 3, 4]) {
        expect(find.text('ชั้นปี $year'), findsWidgets, reason: 'ไม่พบชั้นปี $year');
      }
      // ไม่ควรมีชั้นปี 5 ขึ้นไปในรายการ
      expect(find.text('ชั้นปี 5'), findsNothing);
    });

    testWidgets('ยังไม่ได้เลือกอะไร ต้องไม่มีปุ่มล้างตัวกรองให้กดเล่น', (tester) async {
      await _openStudentsPage(tester);

      expect(find.text('ล้างตัวกรอง'), findsNothing);
    });

    testWidgets('เลือกตัวกรองแล้วปุ่มล้างโผล่ · กดแล้วกลับเป็นค่าเริ่มต้น',
        (tester) async {
      await _openStudentsPage(tester);

      await tester.tap(find.text('ทุกชั้นปี'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ชั้นปี 2').last);
      await tester.pump();

      // ตรวจที่ค่าของตัวกรองเอง — find.text ไม่ชี้ขาด เพราะ DropdownButton เก็บ
      // ข้อความของทุกตัวเลือกไว้ในต้นไม้อยู่แล้ว ไม่ว่าจะเลือกอันไหน
      expect(_yearFilterValue(tester), 2, reason: 'ตัวกรองต้องรับค่าที่เลือก');
      expect(find.text('ล้างตัวกรอง'), findsOneWidget);

      await tester.tap(find.text('ล้างตัวกรอง'));
      await tester.pump();

      expect(_yearFilterValue(tester), isNull, reason: 'ล้างแล้วต้องกลับเป็น "ทุกชั้นปี"');
      expect(find.text('ล้างตัวกรอง'), findsNothing);
    });

    testWidgets('เลือกสถานะก็ทำให้ปุ่มล้างโผล่เหมือนกัน', (tester) async {
      await _openStudentsPage(tester);

      await tester.tap(find.text('สถานะทั้งหมด'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('พ้นสภาพ').last);
      await tester.pump();

      expect(find.text('ล้างตัวกรอง'), findsOneWidget);
    });

    testWidgets('จอแคบ 360 แถบตัวกรองต้องไม่ล้น', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      _loginAsAdmin();

      await tester.pumpWidget(_app());
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
