import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/screens/users_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';

void main() {
  tearDown(() => authService.logout());

  testWidgets('student does not see the "นิสิต" management card but sees "สมัครกิจกรรม" on Home',
      (tester) async {
    authService.token = 'fake-token';
    authService.username = 'student';
    authService.role = 'student';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // ค้นแบบเจาะจง "การ์ดเมนู" เพราะแถบต้อนรับมีป้าย role ที่เขียนว่า "นิสิต" เหมือนกัน
    expect(find.widgetWithText(Card, 'นิสิต'), findsNothing);
    expect(find.text('กิจกรรม'), findsOneWidget);
    expect(find.text('การเข้าร่วมกิจกรรม'), findsOneWidget);
    expect(find.text('สมัครกิจกรรม'), findsOneWidget);
    expect(find.text('ชั่วโมงสะสมของฉัน'), findsOneWidget);
    expect(find.text('ผู้ช่วยอัจฉริยะ'), findsOneWidget);
  });

  testWidgets('Home shows the welcome header, role badge and a labelled logout button',
      (tester) async {
    authService.token = 'fake-token';
    authService.username = '650811001';
    authService.role = 'student';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('สวัสดี, 650811001'), findsOneWidget);
    expect(find.text('นิสิต'), findsOneWidget); // ป้าย role ในแถบต้อนรับ
    expect(find.widgetWithText(OutlinedButton, 'ออกจากระบบ'), findsOneWidget);
  });

  testWidgets('staff does not see "นิสิต" or "จัดการผู้ใช้" cards on Home (admin-only)', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'staff';
    authService.role = 'staff';

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.widgetWithText(Card, 'นิสิต'), findsNothing);
    expect(find.text('จัดการผู้ใช้'), findsNothing);
    expect(find.text('กิจกรรม'), findsOneWidget);
    expect(find.text('สมัครกิจกรรม'), findsNothing);
    expect(find.text('ชั่วโมงสะสมของฉัน'), findsNothing);
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
