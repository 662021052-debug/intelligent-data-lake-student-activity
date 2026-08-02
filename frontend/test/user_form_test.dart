import 'package:activity_tracking_frontend/models/app_user.dart';
import 'package:activity_tracking_frontend/screens/users_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ธีมจริงตั้ง splashFactory เป็น InkRipple ส่วนดีฟอลต์ M3 เป็น InkSparkle ที่ต้อง
// โหลด shader asset ซึ่งไม่มีตอนรัน --no-test-assets
Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

final _staffAccount = AppUser(id: 5, username: 'somsak', role: 'staff');
final _studentAccount =
    AppUser(id: 6, username: '652021002', role: 'student', studentId: 12);

void main() {
  group('สิทธิ์ที่สร้างได้จากหน้าจัดการผู้ใช้', () {
    test('เหลือแค่ staff กับ admin ไม่มีนิสิต', () {
      expect(creatableRoles, ['staff', 'admin']);
      expect(creatableRoles, isNot(contains('student')));
    });
  });

  group('dialog เพิ่มผู้ใช้', () {
    testWidgets('dropdown สิทธิ์ต้องไม่มีตัวเลือก "นิสิต"', (tester) async {
      await tester.pumpWidget(_wrap(const UserFormDialog()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('เจ้าหน้าที่'), findsWidgets);
      expect(find.text('ผู้ดูแลระบบ'), findsWidgets);
      expect(find.text('นิสิต'), findsNothing);
    });

    testWidgets('ต้องไม่มี dropdown "นิสิตที่ผูกบัญชี" เหลืออยู่', (tester) async {
      await tester.pumpWidget(_wrap(const UserFormDialog()));
      await tester.pumpAndSettle();

      expect(find.text('นิสิตที่ผูกบัญชี (ไม่บังคับ)'), findsNothing);
      expect(find.text('— ยังไม่ผูกข้อมูลนิสิต —'), findsNothing);
      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
    });

    testWidgets('มีข้อความบอกทางไปหน้าจัดการนิสิต', (tester) async {
      await tester.pumpWidget(_wrap(const UserFormDialog()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ไปที่หน้าจัดการนิสิต'),
        findsOneWidget,
      );
    });

    testWidgets('เหลือแค่ ชื่อผู้ใช้ / รหัสผ่าน / สิทธิ์', (tester) async {
      await tester.pumpWidget(_wrap(const UserFormDialog()));
      await tester.pumpAndSettle();

      expect(find.text('ชื่อผู้ใช้'), findsOneWidget);
      expect(find.text('รหัสผ่าน'), findsOneWidget);
      expect(find.text('สิทธิ์ (role)'), findsOneWidget);
    });
  });

  group('dialog แก้ไขผู้ใช้', () {
    testWidgets('บัญชี staff ยังเปลี่ยนสิทธิ์ได้', (tester) async {
      await tester.pumpWidget(_wrap(UserFormDialog(existing: _staffAccount)));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      // ข้อความบอกทางเป็นของฟอร์มสร้างใหม่เท่านั้น
      expect(find.textContaining('ไปที่หน้าจัดการนิสิต'), findsNothing);
    });

    testWidgets('บัญชีนิสิตเปลี่ยนสิทธิ์ไม่ได้ แสดงแบบอ่านอย่างเดียว', (tester) async {
      await tester.pumpWidget(_wrap(UserFormDialog(existing: _studentAccount)));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('นิสิต'), findsOneWidget);
      expect(
        find.textContaining('บัญชีนิสิตแก้ได้เฉพาะรหัสผ่าน'),
        findsOneWidget,
      );
    });

    testWidgets('ไม่มีช่องผูกนิสิตให้แก้ในโหมดแก้ไขเช่นกัน', (tester) async {
      await tester.pumpWidget(_wrap(UserFormDialog(existing: _studentAccount)));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
      expect(find.text('นิสิตที่ผูกบัญชี (ไม่บังคับ)'), findsNothing);
    });
  });
}
