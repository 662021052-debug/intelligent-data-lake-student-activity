import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:activity_tracking_frontend/models/student.dart';
import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_form_dialog.dart';

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
  email: 'thanakorn@tsu.ac.th',
);

void main() {
  group('รูปแบบรหัสนิสิต', () {
    test('ว่างเปล่าต้องเตือนให้กรอก', () {
      expect(studentIdValidator(''), 'กรอกรหัสนิสิต');
      expect(studentIdValidator('   '), 'กรอกรหัสนิสิต');
      expect(studentIdValidator(null), 'กรอกรหัสนิสิต');
    });

    test('รับตัวเลข 9-10 หลัก (ข้อมูลจริงเป็น 10 หลัก รุ่นเก่าเป็น 9)', () {
      expect(studentIdValidator('6820510466'), isNull, reason: 'รหัสจริง 10 หลัก');
      expect(studentIdValidator('652021002'), isNull, reason: 'รุ่นเก่า 9 หลัก');
      expect(studentIdValidator('65202100'), isNotNull, reason: 'สั้นไป');
      expect(studentIdValidator('68205104660'), isNotNull, reason: 'ยาวไป');
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

    testWidgets('แบ่งกลุ่ม "ข้อมูลนิสิต" / "บัญชีเข้าใช้งาน" ให้เห็นชัด', (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      expect(find.text('ข้อมูลนิสิต'), findsOneWidget);
      expect(find.text('บัญชีเข้าใช้งาน'), findsOneWidget);
      expect(find.text('ช่องที่มีเครื่องหมาย * จำเป็นต้องกรอก'), findsOneWidget);
      expect(find.byType(FormSectionHeader), findsNWidgets(2));
    });

    testWidgets('โหมดแก้ไขมีเฉพาะกลุ่มข้อมูลนิสิต ไม่มีกลุ่มบัญชี', (tester) async {
      await tester.pumpWidget(_wrap(StudentFormDialog(existing: _existing)));
      await tester.pumpAndSettle();

      expect(find.text('ข้อมูลนิสิต'), findsOneWidget);
      expect(find.text('บัญชีเข้าใช้งาน'), findsNothing);
    });

    testWidgets('ช่องบังคับลงท้ายด้วย * ช่องไม่บังคับบอก (ไม่บังคับ)', (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      for (final label in ['รหัสนิสิต *', 'ชื่อ-สกุล *', 'คณะ *', 'สาขา *', 'ชั้นปี *', 'สถานะ *']) {
        expect(find.text(label), findsOneWidget, reason: 'ไม่พบป้าย "$label"');
      }
      expect(find.text('ชื่อผู้ใช้ (ไม่บังคับ)'), findsOneWidget);
      expect(find.text('รหัสผ่านเริ่มต้น (ไม่บังคับ)'), findsOneWidget);
    });

    testWidgets('ทุกช่องมี label ลอยด้านบนเหมือนกัน ไม่มีช่อง placeholder ล้วน',
        (tester) async {
      // ปัญหาเดิม: M3 เก็บ label ไว้ในช่องที่ยังว่าง แล้วลอยขึ้นเมื่อมีค่า —
      // ช่องที่มีค่าเริ่มต้น (ชั้นปี/สถานะ) จึงดูต่างจากช่องที่เหลือ
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, isNotEmpty);
      for (final field in fields) {
        final decoration = field.decoration!;
        expect(decoration.labelText, isNotNull,
            reason: 'ทุกช่องต้องมี labelText ไม่ใช่ placeholder ลอย');
        expect(decoration.floatingLabelBehavior, FloatingLabelBehavior.always,
            reason: 'label ของ "${decoration.labelText}" ต้องลอยอยู่ด้านบนเสมอ');
      }
    });

    testWidgets('เช็กบ็อกซ์บัญชีวางตัวติ๊กชิดซ้ายและไม่มีระยะขอบส่วนเกิน',
        (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      final tile = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      expect(tile.controlAffinity, ListTileControlAffinity.leading);
      expect(tile.contentPadding, EdgeInsets.zero);

      // ตัวติ๊กต้องอยู่ซ้ายสุดของแถว ไม่ลอยไปกลาง
      final checkbox = tester.getTopLeft(find.byType(Checkbox));
      final title = tester.getTopLeft(find.text('สร้างบัญชีเข้าใช้งานให้ด้วย'));
      expect(checkbox.dx, lessThan(title.dx));
    });

    testWidgets('ฟอร์มเลื่อนได้เมื่อจอเตี้ย', (tester) async {
      tester.view.physicalSize = const Size(800, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'ต้องไม่ overflow บนจอเตี้ย');
    });

    testWidgets('กรอกรหัสนิสิตผิดรูปแบบแล้วกดบันทึก ต้องขึ้น error ไม่ยิง API',
        (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '123');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('รหัสนิสิตต้องเป็นตัวเลข 9-10 หลัก'), findsOneWidget);
    });
  });

  group('อีเมลนิสิต (ไม่บังคับ)', () {
    test('เว้นว่างได้ — ไม่ใช่ทุกคนที่มีอีเมล', () {
      expect(studentEmailValidator(''), isNull);
      expect(studentEmailValidator('   '), isNull);
      expect(studentEmailValidator(null), isNull);
    });

    test('กรอกแล้วต้องพอส่งได้จริง', () {
      expect(studentEmailValidator('6820510466@tsu.ac.th'), isNull);
      expect(studentEmailValidator('  somchai.j@tsu.ac.th  '), isNull, reason: 'ตัดช่องว่างก่อนตรวจ');
      expect(studentEmailValidator('ไม่ใช่อีเมล'), 'รูปแบบอีเมลไม่ถูกต้อง');
      expect(studentEmailValidator('somchai@'), isNotNull, reason: 'ไม่มีโดเมน');
      expect(studentEmailValidator('@tsu.ac.th'), isNotNull, reason: 'ไม่มีชื่อผู้ใช้');
      expect(studentEmailValidator('somchai@tsu'), isNotNull, reason: 'โดเมนไม่มีจุด');
      expect(studentEmailValidator('som chai@tsu.ac.th'), isNotNull, reason: 'มีช่องว่าง');
    });

    test('ที่อยู่ที่เดาจากรหัสนิสิต ใช้ได้เฉพาะเมื่อรหัสถูกรูปแบบ', () {
      expect(suggestedStudentEmail('6820510466'), '6820510466@tsu.ac.th');
      expect(suggestedStudentEmail('  652021002  '), '652021002@tsu.ac.th');
      expect(suggestedStudentEmail(''), isNull);
      expect(suggestedStudentEmail('123'), isNull, reason: 'รหัสยังไม่ครบหลัก');
    });

    test('อีเมลที่ยังไม่ระบุต้องขึ้นว่า "ยังไม่ระบุ" ไม่ใช่ช่องว่าง', () {
      expect(studentEmailLabel(null), 'ยังไม่ระบุ');
      expect(studentEmailLabel(''), 'ยังไม่ระบุ');
      expect(studentEmailLabel('   '), 'ยังไม่ระบุ');
      expect(studentEmailLabel(' somchai@tsu.ac.th '), 'somchai@tsu.ac.th');
    });

    testWidgets('ฟอร์มมีช่องอีเมลที่บอกชัดว่าไม่บังคับ', (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      expect(find.text('อีเมล (ไม่บังคับ)'), findsOneWidget);
      expect(
        find.text('เว้นว่างได้ · ถ้าไม่ระบุ ระบบจะข้ามคนนี้ตอนส่งอีเมลแจ้งเตือน'),
        findsOneWidget,
      );
    });

    testWidgets('โหมดแก้ไขเติมอีเมลเดิมมาให้', (tester) async {
      await tester.pumpWidget(_wrap(StudentFormDialog(existing: _existing)));
      await tester.pumpAndSettle();

      expect(find.text('thanakorn@tsu.ac.th'), findsOneWidget);
    });

    testWidgets('กดปุ่มแล้วเติม {รหัสนิสิต}@tsu.ac.th ให้เอง', (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '6820510466');
      await tester.pumpAndSettle();

      final button = find.widgetWithIcon(IconButton, Icons.alternate_email);
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('6820510466@tsu.ac.th'), findsOneWidget);
    });

    testWidgets('ยังไม่กรอกรหัสนิสิต ปุ่มเติมอีเมลต้องกดไม่ได้', (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      final button = find.widgetWithIcon(IconButton, Icons.alternate_email);
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    });

    testWidgets('กรอกอีเมลผิดรูปแบบแล้วกดบันทึก ต้องขึ้น error ไม่ยิง API',
        (tester) async {
      await tester.pumpWidget(_wrap(const StudentFormDialog()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '6820510466');
      await tester.enterText(find.byType(TextFormField).at(1), 'ทดสอบ ระบบ');
      await tester.enterText(find.byType(TextFormField).at(2), 'วิศวกรรมศาสตร์');
      await tester.enterText(find.byType(TextFormField).at(3), 'วิศวกรรมคอมพิวเตอร์');
      await tester.enterText(find.byType(TextFormField).at(5), 'ไม่ใช่อีเมล');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('รูปแบบอีเมลไม่ถูกต้อง'), findsOneWidget);
    });
  });

}
