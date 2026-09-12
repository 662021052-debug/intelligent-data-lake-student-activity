import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/screens/users_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
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

  testWidgets('admin sees all cards including "จัดการผู้ใช้" on Home', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'admin';
    authService.role = 'admin';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.widgetWithText(Card, 'นิสิต'), findsOneWidget);
    expect(find.text('จัดการผู้ใช้'), findsOneWidget);
    expect(find.text('แดชบอร์ดผู้บริหาร'), findsOneWidget);
    expect(find.text('หมวดชั่วโมงกิจกรรม'), findsOneWidget);
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
