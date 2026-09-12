import 'dart:math' as math;

import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/screens/activity_calendar_screen.dart';
import 'package:activity_tracking_frontend/screens/chatbot_screen.dart';
import 'package:activity_tracking_frontend/screens/checkin_scan_screen.dart';
import 'package:activity_tracking_frontend/screens/dashboard_screen.dart';
import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/screens/hour_categories_screen.dart';
import 'package:activity_tracking_frontend/screens/login_screen.dart';
import 'package:activity_tracking_frontend/screens/my_hours_screen.dart';
import 'package:activity_tracking_frontend/screens/participations_screen.dart';
import 'package:activity_tracking_frontend/screens/register_activities_screen.dart';
import 'package:activity_tracking_frontend/screens/students_screen.dart';
import 'package:activity_tracking_frontend/screens/users_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// อัตราส่วน contrast ตามสูตร WCAG 2.1
double contrast(Color a, Color b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void _loginAs(String role) {
  authService.token = 'fake-token';
  authService.username = role == 'student' ? '662021052' : role;
  authService.role = role;
}

/// ทุกหน้าที่ผู้ใช้เข้าถึงได้ คู่กับ role ที่เข้าหน้านั้นได้จริง
final _screens = <String, (String, Widget Function())>{
  'เข้าสู่ระบบ': ('student', LoginScreen.new),
  'หน้าแรก (นิสิต)': ('student', HomeScreen.new),
  'หน้าแรก (แอดมิน)': ('admin', HomeScreen.new),
  'สมัครกิจกรรม': ('student', RegisterActivitiesScreen.new),
  'รายละเอียดชั่วโมง': ('student', MyHoursScreen.new),
  'ผู้ช่วยอัจฉริยะ': ('student', ChatbotScreen.new),
  'เช็กอิน QR': ('student', CheckinScanScreen.new),
  'จัดการกิจกรรม': ('admin', ActivitiesScreen.new),
  'จัดการผู้ใช้': ('admin', UsersScreen.new),
  'จัดการนิสิต': ('admin', StudentsScreen.new),
  'หมวดชั่วโมง': ('admin', HourCategoriesScreen.new),
  'แดชบอร์ดผู้บริหาร': ('admin', DashboardScreen.new),
  'การเข้าร่วมกิจกรรม': ('admin', ParticipationsScreen.new),
  'ปฏิทินกิจกรรม': ('admin', ActivityCalendarScreen.new),
};

void main() {
  tearDown(() => authService.logout());

  group('responsive — ไม่มีส่วนไหนล้นจอ', () {
    // มือถือเล็กสุดที่ยังต้องรองรับ / แท็บเล็ตแนวตั้ง / เดสก์ท็อป
    const sizes = <String, Size>{
      'จอแคบ 360': Size(360, 740),
      'แท็บเล็ต 768': Size(768, 1024),
      'เดสก์ท็อป 1440': Size(1440, 900),
    };

    for (final entry in _screens.entries) {
      final (role, build) = entry.value;
      for (final size in sizes.entries) {
        testWidgets('${entry.key} @ ${size.key}', (tester) async {
          tester.view.physicalSize = size.value;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          _loginAs(role);
          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            home: build(),
          ));
          // ปล่อยให้คำขอที่ล้มเหลว (ไม่มีเซิร์ฟเวอร์ในเทสต์) จบก่อน
          // ไม่ใช้ pumpAndSettle เพราะบางหน้ามีวงหมุนที่หมุนไม่จบ
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));

          // RenderFlex overflow / ข้อความล้น จะโยน exception ออกมาตรงนี้
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} ล้นจอที่ความกว้าง ${size.value.width}',
          );
        });
      }
    }
  });

  group('contrast — ตัวอักษรและกราฟิกผ่านเกณฑ์ WCAG AA', () {
    const card = AppColors.surface;
    const page = AppColors.page;

    test('สีตัวอักษรบนการ์ดขาวผ่าน 4.5:1', () {
      expect(contrast(AppColors.ink, card), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.sub, card), greaterThanOrEqualTo(4.5));
      // สีจางที่ใช้กับหัวตาราง/คำอธิบายย่อย ก็ยังต้องอ่านออก
      expect(contrast(AppColors.muted, card), greaterThanOrEqualTo(4.5));
    });

    test('สีตัวอักษรบนพื้นหน้าสีเทาผ่าน 4.5:1', () {
      expect(contrast(AppColors.ink, page), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.sub, page), greaterThanOrEqualTo(4.5));
    });

    test('ลำดับความสำคัญของตัวอักษรยังไล่จากเข้มไปจาง', () {
      expect(contrast(AppColors.ink, card), greaterThan(contrast(AppColors.sub, card)));
      expect(contrast(AppColors.sub, card), greaterThan(contrast(AppColors.muted, card)));
    });

    test('ตัวอักษรบนชิปสถานะทุกสีผ่าน 4.5:1', () {
      const palettes = {
        'อนุมัติ': StatusPalette.approved,
        'รอตรวจ': StatusPalette.pending,
        'ไม่อนุมัติ': StatusPalette.rejected,
        'กลาง': StatusPalette.neutral,
        'ข้อมูล': StatusPalette.info,
      };
      palettes.forEach((name, p) {
        expect(
          contrast(p.foreground, p.background),
          greaterThanOrEqualTo(4.5),
          reason: 'ชิป "$name" ตัวอักษรจางเกินไป',
        );
      });
    });

    test('ตัวอักษรบนปุ่มผ่าน 4.5:1', () {
      expect(contrast(Colors.white, AppColors.blue), greaterThanOrEqualTo(4.5));
      expect(contrast(Colors.white, AppColors.dark), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.ink, card), greaterThanOrEqualTo(4.5));
    });

    test('ตัวอักษรบนเมนู sidebar และแถบบนผ่าน 4.5:1', () {
      // เมนูพื้นน้ำเงินเข้ม: ตัวอักษรปกติ หัวข้อกลุ่ม และเมนูที่เปิดอยู่ (พื้นขาวตัวฟ้า)
      expect(contrast(AppColors.onNav, AppColors.blueDark), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.onNavMuted, AppColors.blueDark), greaterThanOrEqualTo(4.5));
      expect(contrast(Colors.white, AppColors.blueDark), greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.blue, Colors.white), greaterThanOrEqualTo(4.5));
      // แถบบนพื้นฟ้าตัวขาว + ป้ายบทบาทพื้นขาวตัวฟ้า
      expect(contrast(Colors.white, AppColors.blue), greaterThanOrEqualTo(4.5));
      // ลำดับความสำคัญบนเมนูยังไล่จากสว่างไปจาง
      expect(
        contrast(AppColors.onNav, AppColors.blueDark),
        greaterThan(contrast(AppColors.onNavMuted, AppColors.blueDark)),
      );
    });

    test('กราฟิกที่สื่อความหมายผ่าน 3:1 บนพื้นที่มันวางอยู่', () {
      // แถบความคืบหน้า/แท่งกราฟ วางบนรางสีพื้นหน้า
      for (final accent in [
        StatusPalette.approved.accent,
        StatusPalette.pending.accent,
        StatusPalette.rejected.accent,
        AppColors.blue,
      ]) {
        expect(contrast(accent, page), greaterThanOrEqualTo(3.0));
      }
      // ขอบช่องกรอกเป็นสิ่งเดียวที่บอกขอบเขตของช่อง
      expect(contrast(AppColors.fieldBorder, card), greaterThanOrEqualTo(3.0));
    });
  });
}
