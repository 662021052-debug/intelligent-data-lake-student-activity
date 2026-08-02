// F1 — หน้าเช็กอินหน้างานด้วย QR
//
// เทสต์ไม่แตะกล้องจริง: หน้าจอจงใจไม่เปิดกล้องเองตอนเข้าหน้า (ต้องกดปุ่มก่อน
// เพื่อให้เบราว์เซอร์ถามสิทธิ์ตอนผู้ใช้ตั้งใจสแกน) จึงทดสอบสถานะเริ่มต้น
// ทางเลือกกรอกรหัสมือ และการกันส่งช่องว่าง ได้โดยไม่ต้องมี platform channel
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:activity_tracking_frontend/screens/checkin_scan_screen.dart';
import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/format.dart';

void _loginAs(String role) {
  authService.token = 'fake-token';
  authService.username = role;
  authService.role = role;
}

void main() {
  tearDown(() => authService.logout());

  testWidgets('นิสิตเห็นการ์ด "เช็กอินหน้างาน" บนหน้าหลัก', (tester) async {
    _loginAs('student');
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('เช็กอินหน้างาน'), findsOneWidget);
  });

  testWidgets('เจ้าหน้าที่/ผู้ดูแลไม่เห็นการ์ดเช็กอิน (เป็นการกระทำของนิสิตเท่านั้น)',
      (tester) async {
    for (final role in ['staff', 'admin']) {
      _loginAs(role);
      await tester.pumpWidget(MaterialApp(home: const HomeScreen(), key: Key(role)));
      expect(find.text('เช็กอินหน้างาน'), findsNothing);
    }
  });

  testWidgets('หน้าเช็กอินไม่เปิดกล้องเอง แต่แสดงคำอธิบาย + ปุ่มเปิดกล้อง + ทางเลือกกรอกรหัส',
      (tester) async {
    _loginAs('student');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CheckinScanScreen()));

    expect(find.text('สแกน QR ของกิจกรรมที่หน้างาน'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'เปิดกล้องสแกน QR'), findsOneWidget);
    expect(find.text('กล้องใช้ไม่ได้ — กรอกรหัสกิจกรรมแทน'), findsOneWidget);
  });

  testWidgets('บอกชัดว่าเช็กอินยังไม่ได้ชั่วโมง (กฎ D2)', (tester) async {
    _loginAs('student');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CheckinScanScreen()));

    expect(
      find.textContaining('ชั่วโมงกิจกรรมจะนับให้เมื่อส่งหลักฐานและเจ้าหน้าที่อนุมัติแล้ว'),
      findsOneWidget,
    );
  });

  testWidgets('กดทางเลือกกรอกรหัสแล้วได้ช่องกรอก (fallback ตอนกล้องใช้ไม่ได้)',
      (tester) async {
    _loginAs('student');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CheckinScanScreen()));

    await tester.tap(find.text('กล้องใช้ไม่ได้ — กรอกรหัสกิจกรรมแทน'));
    await tester.pumpAndSettle();

    expect(find.text('กรอกรหัสกิจกรรม'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'เช็กอิน'), findsOneWidget);
  });

  testWidgets('กดเช็กอินโดยไม่กรอกรหัส → เตือนเป็นภาษาไทย ไม่ยิงคำขอ', (tester) async {
    _loginAs('student');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CheckinScanScreen()));

    await tester.tap(find.text('กล้องใช้ไม่ได้ — กรอกรหัสกิจกรรมแทน'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'เช็กอิน'));
    await tester.pump();

    expect(find.text('กรอกรหัสกิจกรรมก่อนกดเช็กอิน'), findsOneWidget);
  });

  testWidgets('บทบาทอื่นเปิดหน้านี้ตรง ๆ ไม่ได้', (tester) async {
    _loginAs('staff');
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: const CheckinScanScreen()));
    expect(find.text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้'), findsOneWidget);
  });

  group('serverTimeToLocal', () {
    test('เวลาที่ backend ส่งมาแบบไม่มีโซน ถือเป็น UTC แล้วแปลงเป็นเวลาเครื่อง', () {
      // สิ่งที่ Participation.fromJson ได้จาก "2026-08-02T09:15:00" (ไม่มี Z)
      final parsed = DateTime.parse('2026-08-02T09:15:00');
      expect(parsed.isUtc, isFalse); // Dart อ่านเป็นเวลาท้องถิ่นตามตัวอักษร

      // ค่าจริงคือ 09:15 UTC จึงต้องได้จุดเวลาเดียวกับ DateTime.utc(...).toLocal()
      expect(serverTimeToLocal(parsed), equals(DateTime.utc(2026, 8, 2, 9, 15).toLocal()));
    });

    test('ค่าที่เป็น UTC อยู่แล้วแปลงเป็นเวลาเครื่องตรง ๆ', () {
      final utc = DateTime.utc(2026, 8, 2, 9, 15);
      expect(serverTimeToLocal(utc), equals(utc.toLocal()));
    });
  });
}
