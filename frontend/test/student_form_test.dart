import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:activity_tracking_frontend/models/student.dart';
import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';

// ต้องใช้ธีมจริง — ธีมของแอปตั้ง splashFactory เป็น InkRipple ส่วนดีฟอลต์ M3
// เป็น InkSparkle ที่ต้องโหลด shader asset ซึ่งไม่มีตอนรัน --no-test-assets
Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

final _existing = Student(
  id: 1,
  studentId: '652021002',
  fullName: 'ธนกร นวลจันทร์',
  faculty: 'วิศวกรรมศาสตร์',
  major: 'วิศวกรรมคอมพิวเตอร์',
  yearLevel: 4,
  status: 'active',
);

void main() {
  group('รูปแบบรหัสนิสิต', () {
    test('ว่างเปล่าต้องเตือนให้กรอก', () {
      expect(studentIdValidator(''), 'กรอกรหัสนิสิต');
      expect(studentIdValidator('   '), 'กรอกรหัสนิสิต');
      expect(studentIdValidator(null), 'กรอกรหัสนิสิต');
    });

    test('ต้องเป็นตัวเลข 9 หลักเท่านั้น', () {
      expect(studentIdValidator('652021002'), isNull);
      expect(studentIdValidator('65202100'), isNotNull, reason: 'สั้นไป');
      expect(studentIdValidator('6520210022'), isNotNull, reason: 'ยาวไป');
      expect(studentIdValidator('65202100a'), isNotNull, reason: 'มีตัวอักษร');
      expect(studentIdValidator('652-021-0'), isNotNull, reason: 'มีขีด');
    });

    test('ตัดช่องว่างหัวท้ายก่อนตรวจ', () {
      expect(studentIdValidator('  652021002  '), isNull);
    });
  });

  group('ข้อความแจ้งหลังสร้างบัญชี', () {
    test('ใช้ค่าเริ่มต้น — บอกว่ารหัสผ่านคือรหัสนิสิต', () {
      final message = accountCreatedMessage('652021002', customPassword: false);
      expect(message, contains('652021002'));
      expect(message, contains('รหัสผ่านเริ่มต้น: รหัสนิสิต'));
      expect(message, contains('แนะนำให้เปลี่ยน'));
    });

    test('ตั้งรหัสผ่านเอง — ต้องไม่ไปบอกว่าเป็นรหัสนิสิต', () {
      final message = accountCreatedMessage('somchai.j', customPassword: true);
      expect(message, contains('somchai.j'));
      expect(message, contains('ตามที่กำหนดไว้'));
      expect(message, isNot(contains('รหัสผ่านเริ่มต้น: รหัสนิสิต')));
    });
  });

  group('ฟอร์มเพิ่มนิสิต', () {
    testWidgets('ตอนสร้างใหม่และติ๊กสร้างบัญชี ต้องมีช่องชื่อผู้ใช้/รหัสผ่าน',
        (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      expect(find.text('สร้างบัญชีเข้าใช้งานให้ด้วย'), findsOneWidget);
      expect(find.text('ชื่อผู้ใช้ (ไม่บังคับ)'), findsOneWidget);
      expect(find.text('รหัสผ่านเริ่มต้น (ไม่บังคับ)'), findsOneWidget);
      // ต้องบอกให้ชัดว่าเว้นว่างแล้วจะได้อะไร
      expect(find.text('เว้นว่าง = ใช้รหัสนิสิต'), findsOneWidget);
    });

    testWidgets('ปลดติ๊กสร้างบัญชี ช่องชื่อผู้ใช้/รหัสผ่านต้องหายไป', (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      // ฟอร์มอยู่ใน SingleChildScrollView — ต้องเลื่อนให้เห็นก่อน ไม่งั้น tap
      // จะไปตกนอกพื้นที่ hit-test แล้วเทสต์ผ่านแบบบังเอิญ
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      expect(find.text('ชื่อผู้ใช้ (ไม่บังคับ)'), findsNothing);
      expect(find.text('รหัสผ่านเริ่มต้น (ไม่บังคับ)'), findsNothing);
    });

    testWidgets('โหมดแก้ไข ต้องไม่มีทั้งช่องติ๊กและช่องบัญชี', (tester) async {
      await tester.pumpWidget(_wrap(StudentFormDialog(existing: _existing)));
      await tester.pumpAndSettle();

      expect(find.text('สร้างบัญชีเข้าใช้งานให้ด้วย'), findsNothing);
      expect(find.text('ชื่อผู้ใช้ (ไม่บังคับ)'), findsNothing);
      expect(find.text('รหัสผ่านเริ่มต้น (ไม่บังคับ)'), findsNothing);
      // แต่ต้องเติมข้อมูลเดิมมาให้ครบ
      expect(find.text('652021002'), findsOneWidget);
      expect(find.text('ธนกร นวลจันทร์'), findsOneWidget);
    });

    testWidgets('กรอกรหัสนิสิตผิดรูปแบบแล้วกดบันทึก ต้องขึ้น error ไม่ยิง API',
        (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '123');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('รหัสนิสิตต้องเป็นตัวเลข 9 หลัก'), findsOneWidget);
    });
  });
}
