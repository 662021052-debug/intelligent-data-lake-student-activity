import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:activity_tracking_frontend/screens/dashboard_screen.dart';
import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/screens/users_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/admin_console.dart';
import 'package:activity_tracking_frontend/widgets/app_sidebar.dart';

void main() {
  tearDown(() => authService.logout());

  testWidgets('นิสิตไม่เห็นทางเข้าหน้าจัดการนิสิต แต่เห็นทางลัดของตัวเองบนหน้าแรก',
      (tester) async {
    authService.token = 'fake-token';
    authService.username = 'student';
    authService.role = 'student';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // หน้าแรกของนิสิตเป็นแผงโปรไฟล์ + ชั่วโมง ไม่มีแผงจัดการของผู้ดูแล
    expect(find.widgetWithText(Card, 'นิสิต'), findsNothing);
    expect(find.text('จัดการผู้ใช้'), findsNothing);
    expect(find.text('แดชบอร์ดผู้บริหาร'), findsNothing);

    // ทางลัดของนิสิต — สี่หน้าที่ไม่ได้อยู่บนแถบเมนูด้านบน
    expect(find.text('ทางลัด'), findsOneWidget);
    expect(find.text('เช็กอินหน้างาน'), findsOneWidget);
    expect(find.text('การเข้าร่วมกิจกรรม'), findsOneWidget);
    expect(find.text('กิจกรรม'), findsOneWidget);
    expect(find.text('ปฏิทินกิจกรรม'), findsOneWidget);
  });

  testWidgets('แถบบนของนิสิตมีเมนูของนิสิตและปุ่มออกจากระบบ', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    authService.token = 'fake-token';
    authService.username = '650811001';
    authService.role = 'student';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.text('หน้าแรก'), findsOneWidget);
    expect(find.text('สมัครกิจกรรม'), findsOneWidget);
    expect(find.text('รายละเอียดชั่วโมง'), findsOneWidget);
    expect(find.text('ผู้ช่วยอัจฉริยะ'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'ออกจากระบบ'), findsOneWidget);
    // avatar ใช้ตัวอักษรแรกของรหัสนิสิต
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('staff does not see "นิสิต" or "จัดการผู้ใช้" cards on Home (admin-only)', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'staff';
    authService.role = 'staff';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.widgetWithText(Card, 'นิสิต'), findsNothing);
    expect(find.text('จัดการผู้ใช้'), findsNothing);
    expect(find.text('หมวดชั่วโมงกิจกรรม'), findsNothing);
    expect(find.text('กิจกรรม'), findsOneWidget);
    expect(find.text('สมัครกิจกรรม'), findsNothing);
    expect(find.text('แดชบอร์ดชั่วโมงของฉัน'), findsNothing);
    expect(find.text('ผู้ช่วยอัจฉริยะ'), findsNothing);
  });

  testWidgets('แอดมินล็อกอินแล้ว landing ที่แดชบอร์ดคอนโซล ไม่ใช่แผงการ์ดเมนูเดิม',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    authService.token = 'fake-token';
    authService.username = 'admin';
    authService.role = 'admin';

    // HomeScreen คือหน้าที่แอปพาไปหลังล็อกอิน — แอดมินต้องเจอคอนโซลทันทีโดยไม่ต้องกดต่อ
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);

    // แถบคู่มือต้อง "แสดงจริง" ไม่ใช่แค่มีในโค้ด — เช็กทั้งตัว widget ข้อความ ปุ่ม
    // และสีพื้นน้ำเงินเข้มที่วาดออกมา
    expect(find.byType(GuideBanner), findsOneWidget);
    expect(find.text('คู่มือการใช้งานสำหรับ Admin'), findsOneWidget);
    expect(find.text('ตั้งแต่ตั้งค่ากิจกรรมจนออกใบประมวลผล'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'เปิดคู่มือ →'), findsOneWidget);
    final banner = tester.widget<Container>(
      find.descendant(of: find.byType(GuideBanner), matching: find.byType(Container)).first,
    );
    expect((banner.decoration as BoxDecoration).color, AppColors.blueDark);

    // แผงการ์ดเมนูเดิมหายไป แต่ทุกหน้าที่มันเคยพาไปต้องยังเข้าถึงได้
    expect(find.text('หมวดชั่วโมงกิจกรรม'), findsNothing, reason: 'ชื่อการ์ดของแผงเดิม');
    for (final label in [
      'จัดการกิจกรรม',
      'จัดการผู้ใช้',
      'หมวดชั่วโมง',
      'รีเฟรช Gold',
      'การเข้าร่วมกิจกรรม',
      'ปฏิทินกิจกรรม',
    ]) {
      expect(find.widgetWithText(OutlinedButton, label), findsOneWidget, reason: label);
    }
    // จัดการนิสิตย้ายขึ้นเมนู sidebar ตาม mockup
    expect(
      find.descendant(of: find.byType(AppSidebar), matching: find.text('จัดการนิสิต')),
      findsOneWidget,
    );
  });

  testWidgets('non-admin roles do not see the "แดชบอร์ดผู้บริหาร" card', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'staff';
    authService.role = 'staff';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('แดชบอร์ดผู้บริหาร'), findsNothing);
  });

  testWidgets('StudentsScreen refuses to render its content for a student role', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'student';
    authService.role = 'student';

    await tester.pumpWidget(const MaterialApp(home: StudentsScreen()));

    expect(find.text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้'), findsOneWidget);
  });

  testWidgets('StudentsScreen refuses to render its content for a staff role (admin-only)', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'staff';
    authService.role = 'staff';

    await tester.pumpWidget(const MaterialApp(home: StudentsScreen()));

    expect(find.text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้'), findsOneWidget);
  });

  testWidgets('UsersScreen refuses to render its content for a staff role', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'staff';
    authService.role = 'staff';

    await tester.pumpWidget(const MaterialApp(home: UsersScreen()));

    expect(find.text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้'), findsOneWidget);
  });
}
