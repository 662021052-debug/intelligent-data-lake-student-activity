import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/screens/hour_categories_screen.dart';
import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/screens/users_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_buttons.dart';
import 'package:activity_tracking_frontend/widgets/app_card.dart';
import 'package:activity_tracking_frontend/widgets/app_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// หน้าฝั่งผู้ดูแลยิง API ตอนเปิด ซึ่งในเทสต์ล้มเหลว — ที่ตรวจคือโครงหน้า
/// (แถบเมนู หัวข้อ ปุ่มหลัก สิทธิ์) ไม่ใช่ข้อมูลที่โหลดมา
Widget _app(Widget home) => MaterialApp(theme: AppTheme.light, home: home);

void _loginAs(String role) {
  authService.token = 'fake-token';
  authService.username = role;
  authService.role = role;
}

void _wideScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  tearDown(() => authService.logout());

  group('แถบเมนูฝั่งผู้ดูแล', () {
    testWidgets('แอดมินเห็นเมนูผู้ดูแลครบสี่ช่อง และ "จัดการกิจกรรม" เป็นช่องที่เปิดอยู่',
        (tester) async {
      _wideScreen(tester);
      _loginAs('admin');
      await tester.pumpWidget(_app(const ActivitiesScreen()));

      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.text('ระบบผู้ดูแล'), findsOneWidget);
      expect(find.text('จัดการผู้ใช้'), findsOneWidget);
      expect(find.text('หมวดชั่วโมง'), findsOneWidget);
      expect(find.text('แดชบอร์ด'), findsOneWidget);

      // ช่อง "จัดการกิจกรรม" บนเมนู + หัวข้อหน้า = สองที่ และช่องเมนูต้องเป็นสีฟ้า
      final navLabel = tester.widgetList<Text>(find.text('จัดการกิจกรรม'));
      expect(navLabel.length, 2);
      expect(navLabel.any((t) => t.style?.color == AppColors.blue), isTrue);
    });

    testWidgets('เจ้าหน้าที่ไม่เห็นเมนูที่เป็นของแอดมินเท่านั้น', (tester) async {
      _wideScreen(tester);
      _loginAs('staff');
      await tester.pumpWidget(_app(const ActivitiesScreen()));

      expect(find.text('จัดการผู้ใช้'), findsNothing);
      expect(find.text('หมวดชั่วโมง'), findsNothing);
      expect(find.text('แดชบอร์ด'), findsNothing);
      expect(find.text('การเข้าร่วมกิจกรรม'), findsOneWidget);
    });
  });

  group('หน้าจัดการกิจกรรม', () {
    testWidgets('เจ้าหน้าที่มีปุ่มสร้างและปุ่มนำเข้าอยู่ที่หัวข้อหน้า', (tester) async {
      _wideScreen(tester);
      _loginAs('staff');
      await tester.pumpWidget(_app(const ActivitiesScreen()));

      expect(find.widgetWithText(FilledButton, 'สร้างกิจกรรม'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'นำเข้าแผนกิจกรรม'), findsOneWidget);
      // ปุ่มลอยมุมขวาล่างถูกย้ายขึ้นมาไว้ที่หัวข้อหน้าแล้ว
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('นิสิตไม่มีปุ่มสร้าง/นำเข้า และหัวข้อเป็น "กิจกรรม"', (tester) async {
      _wideScreen(tester);
      _loginAs('student');
      await tester.pumpWidget(_app(const ActivitiesScreen()));

      expect(find.text('กิจกรรม'), findsOneWidget);
      expect(find.text('จัดการกิจกรรม'), findsNothing);
      expect(find.text('สร้างกิจกรรม'), findsNothing);
      expect(find.text('นำเข้าแผนกิจกรรม'), findsNothing);
    });
  });

  group('หน้าจัดการผู้ใช้', () {
    testWidgets('แอดมินเห็นหัวข้อ + ปุ่มเพิ่มผู้ใช้', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');
      await tester.pumpWidget(_app(const UsersScreen()));

      expect(find.text('จัดการผู้ใช้'), findsNWidgets(2)); // เมนูบน + หัวข้อหน้า
      expect(find.widgetWithText(FilledButton, 'เพิ่มผู้ใช้'), findsOneWidget);
    });

    testWidgets('เจ้าหน้าที่เข้าไม่ได้ แต่ยังมีแถบเมนูให้ไปหน้าอื่นต่อ', (tester) async {
      _wideScreen(tester);
      _loginAs('staff');
      await tester.pumpWidget(_app(const UsersScreen()));

      expect(find.text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้'), findsOneWidget);
      expect(find.byType(AppSidebar), findsOneWidget);
    });
  });

  group('หน้าจัดการนิสิต', () {
    testWidgets('แอดมินเห็นหัวข้อ + ปุ่มเพิ่มนิสิต', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');
      await tester.pumpWidget(_app(const StudentsScreen()));

      // ชื่อเดียวกันอยู่บนเมนู sidebar ด้วย — นับเฉพาะหัวข้อในเนื้อหาของหน้า
      expect(
        find.descendant(of: find.byType(SectionHeader), matching: find.text('จัดการนิสิต')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AppSidebar), matching: find.text('จัดการนิสิต')),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'เพิ่มนิสิต'), findsOneWidget);
    });
  });

  group('หน้าหมวดชั่วโมง', () {
    testWidgets('แอดมินเห็นหัวข้อ + ปุ่มหลักปุ่มเดียว "เพิ่มชุดเกณฑ์ใหม่"', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');
      await tester.pumpWidget(_app(const HourCategoriesScreen()));

      expect(find.text('หมวดชั่วโมงกิจกรรม'), findsOneWidget);
      // ปุ่มระดับหน้ามีปุ่มเดียว = สร้างเกณฑ์รุ่นใหม่ · "เพิ่มหมวดใหญ่" ของโครงเก่าต้องไม่อยู่
      // บนหัวข้อหน้าอีก (ย้ายไปอยู่ในกรอบ "เกณฑ์เดิม" — เทสอยู่ที่ criteria_set_management_test)
      expect(find.widgetWithText(FilledButton, 'เพิ่มชุดเกณฑ์ใหม่'), findsOneWidget);
      // ปุ่ม "เพิ่ม…" ทั้งหน้ามีตัวเดียว (ปุ่มอื่นของเปลือกหน้า เช่น ลองใหม่ ไม่นับ)
      expect(
        find.ancestor(
          of: find.textContaining('เพิ่ม'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('เพิ่มหมวดใหญ่'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('ปุ่มจัดการในตาราง', () {
    testWidgets('ปุ่มโหลดใหม่เป็นปุ่มไอคอนกรอบเทาที่มี tooltip', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');
      await tester.pumpWidget(_app(const UsersScreen()));

      expect(find.byType(AppIconButton), findsWidgets);
      expect(find.byTooltip('โหลดใหม่'), findsOneWidget);
    });
  });
}
