import 'package:flutter_test/flutter_test.dart';

import 'package:activity_tracking_frontend/main.dart';

void main() {
  testWidgets('shows login screen when not authenticated', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    expect(find.text('ชื่อผู้ใช้'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsOneWidget);
  });

  testWidgets('shows validation errors on empty submit', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('เข้าสู่ระบบ'));
    await tester.pump();

    expect(find.text('กรอกชื่อผู้ใช้'), findsOneWidget);
    expect(find.text('กรอกรหัสผ่าน'), findsOneWidget);
  });
}
