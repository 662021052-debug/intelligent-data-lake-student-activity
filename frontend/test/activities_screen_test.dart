import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _labelOf(DataColumn column) => ((column.label as Text).data)!;

void main() {
  tearDown(() => authService.logout());

  group('คอลัมน์ตารางกิจกรรม', () {
    test('มุมมองนิสิตไม่มีคอลัมน์ "สถานะอนุมัติ"', () {
      final labels = activityTableColumns(true).map(_labelOf);
      expect(labels, isNot(contains('สถานะอนุมัติ')));
    });

    test('มุมมอง staff/admin ยังมีคอลัมน์ "สถานะอนุมัติ" เหมือนเดิม', () {
      final labels = activityTableColumns(false).map(_labelOf);
      expect(labels, contains('สถานะอนุมัติ'));
    });

    test('ตัดออกแค่คอลัมน์เดียว คอลัมน์อื่นครบเหมือนเดิม', () {
      final student = activityTableColumns(true).map(_labelOf).toList();
      final staff = activityTableColumns(false).map(_labelOf).toList();

      expect(staff.length - student.length, 1);
      for (final label in ['ชื่อกิจกรรม', 'ประเภท', 'หมวดชั่วโมง', 'ชั่วโมง', 'วันเวลา', 'สถานที่']) {
        expect(student, contains(label), reason: 'นิสิตต้องยังเห็นคอลัมน์ $label');
      }
    });
  });

  group('สิทธิ์เขียนของนิสิต', () {
    test('นิสิตไม่มีสิทธิ์เขียน — ปุ่มอนุมัติ/QR/แก้ไข/ลบ จึงไม่ถูก render', () {
      // _actionButtons (ที่มีปุ่ม "อนุมัติกิจกรรม") ผูกกับ canWrite ทั้งในตารางและ
      // การ์ด ถ้า canWrite ของนิสิตเป็น true เมื่อไหร่ ปุ่มอนุมัติจะหลุดทันที
      authService.role = 'student';
      expect(authService.canWrite, isFalse);
      expect(authService.isAdmin, isFalse);

      authService.role = 'staff';
      expect(authService.canWrite, isTrue);

      authService.role = 'admin';
      expect(authService.canWrite, isTrue);
      expect(authService.isAdmin, isTrue);
    });
  });

  testWidgets('หัวข้อหน้าต่างกันตาม role — นิสิตเห็น "กิจกรรม" ไม่ใช่ "จัดการกิจกรรม"',
      (tester) async {
    authService.token = 'fake-token';
    authService.username = 'student';
    authService.role = 'student';

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const ActivitiesScreen(),
    ));

    // หัวข้อหน้าอยู่ใน SectionHeader ของเนื้อหา (แถบบนเป็นเมนูหลักของระบบแล้ว)
    expect(find.text('กิจกรรม'), findsOneWidget);
    expect(find.text('จัดการกิจกรรม'), findsNothing);
    // นิสิตต้องไม่มีปุ่มสร้าง/นำเข้ากิจกรรม
    expect(find.text('สร้างกิจกรรม'), findsNothing);
    expect(find.text('นำเข้าแผนกิจกรรม'), findsNothing);
  });
}
