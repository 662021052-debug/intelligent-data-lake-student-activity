import 'package:activity_tracking_frontend/screens/activity_calendar_screen.dart';
import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => authService.logout());

  group('การเข้าถึงจากหน้า Home', () {
    for (final role in ['student', 'staff', 'admin']) {
      testWidgets('role $role เห็นการ์ด "ปฏิทินกิจกรรม"', (tester) async {
        authService.token = 'fake-token';
        authService.username = role;
        authService.role = role;

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

        expect(find.text('ปฏิทินกิจกรรม'), findsOneWidget);
      });
    }
  });

  group('รูปแบบวันที่ภาษาไทย', () {
    // ปฏิทินไม่ได้พึ่ง locale data ของ intl จึงต้องแปลงเองให้ถูก
    test('หัวปฏิทินเป็นชื่อเดือนไทย + ปีพุทธศักราช', () {
      expect(thaiMonthTitle(DateTime(2026, 10, 14)), 'ตุลาคม 2569');
      expect(thaiMonthTitle(DateTime(2025, 1, 1)), 'มกราคม 2568');
      expect(thaiMonthTitle(DateTime(2026, 12, 31)), 'ธันวาคม 2569');
    });

    test('ชื่อวันย่อเรียงแบบสัปดาห์เริ่มวันจันทร์', () {
      expect(thaiWeekdayLabel(DateTime(2026, 8, 3)), 'จ.'); // จันทร์
      expect(thaiWeekdayLabel(DateTime(2026, 8, 6)), 'พฤ.'); // พฤหัสบดี
      expect(thaiWeekdayLabel(DateTime(2026, 8, 9)), 'อา.'); // อาทิตย์
    });
  });

  testWidgets('เปิดหน้าปฏิทินได้โดยไม่ crash และมี AppBar ของตัวเอง', (tester) async {
    authService.token = 'fake-token';
    authService.username = 'student';
    authService.role = 'student';

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const ActivityCalendarScreen(),
    ));

    expect(find.widgetWithText(AppBar, 'ปฏิทินกิจกรรม'), findsOneWidget);
    // ระหว่างโหลดต้องมีตัวหมุน ไม่ใช่จอว่าง
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
