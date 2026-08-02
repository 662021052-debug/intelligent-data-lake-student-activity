// F4a/F4b — สแกน QR ด้วยกล้องปกติแล้วเด้งเข้าเว็บเช็กอิน
//
// ครอบคลุมสามเรื่อง: อ่าน token จาก route ที่แอปถูกเปิดมา, หน้ายืนยันแยกตาม
// บทบาทของบัญชี, และการที่ token ไม่หายตอนถูกพาไปหน้า login
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:activity_tracking_frontend/screens/checkin_confirm_screen.dart';
import 'package:activity_tracking_frontend/screens/login_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/services/pending_checkin.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';

const _token = 'b97e85b0dd544be29d3b73063bfb5883';

void _loginAs(String role) {
  authService.token = 'fake-token';
  authService.username = role == 'student' ? '650811001' : role;
  authService.role = role;
}

Future<void> _pumpConfirm(WidgetTester tester, {VoidCallback? onDone}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: CheckinConfirmScreen(token: _token, onDone: onDone ?? () {}),
    ),
  );
}

void main() {
  tearDown(() {
    authService.logout();
    pendingCheckin.clear();
  });

  group('PendingCheckin อ่าน token จาก route', () {
    // Flutter web ใช้ hash routing: URL `https://host/#/checkin?c=x` มาถึงแอป
    // เป็น route `/checkin?c=x`
    test('route ของ deep link → ได้ token', () {
      pendingCheckin.readFromAppStart(route: '/checkin?c=$_token');
      expect(pendingCheckin.token, _token);
      expect(pendingCheckin.hasPending, isTrue);
    });

    test('มี slash ท้าย path ก็ยังอ่านได้', () {
      pendingCheckin.readFromAppStart(route: '/checkin/?c=$_token');
      expect(pendingCheckin.token, _token);
    });

    test('มีพารามิเตอร์อื่นปนมาก็ยังอ่านได้', () {
      pendingCheckin.readFromAppStart(route: '/checkin?from=poster&c=$_token');
      expect(pendingCheckin.token, _token);
    });

    test('เปิดแอปตามปกติ → ไม่มี token ค้าง', () {
      pendingCheckin.readFromAppStart(route: '/');
      expect(pendingCheckin.hasPending, isFalse);
    });

    test('route อื่นที่บังเอิญมี c= → ไม่นับเป็นเช็กอิน', () {
      pendingCheckin.readFromAppStart(route: '/activities?c=$_token');
      expect(pendingCheckin.hasPending, isFalse);
    });

    test('ลิงก์เช็กอินที่ไม่มี token → ไม่มี token ค้าง', () {
      pendingCheckin.readFromAppStart(route: '/checkin');
      expect(pendingCheckin.hasPending, isFalse);
      pendingCheckin.readFromAppStart(route: '/checkin?c=');
      expect(pendingCheckin.hasPending, isFalse);
    });

    test('route ว่าง/null ไม่พัง', () {
      pendingCheckin.readFromAppStart(route: null);
      expect(pendingCheckin.hasPending, isFalse);
      pendingCheckin.readFromAppStart(route: '');
      expect(pendingCheckin.hasPending, isFalse);
    });

    test('clear() แล้วกลับไปสถานะปกติ', () {
      pendingCheckin.readFromAppStart(route: '/checkin?c=$_token');
      pendingCheckin.clear();
      expect(pendingCheckin.hasPending, isFalse);
    });
  });

  group('PendingCheckin อ่าน token จาก URL ของหน้า (เผื่อ route ไม่ได้พามา)', () {
    test('URL แบบ hash routing — ค่าที่ QR เก็บจริง', () {
      pendingCheckin.readFromAppStart(
        url: Uri.parse('https://activity.tsu.ac.th/#/checkin?c=$_token'),
      );
      expect(pendingCheckin.token, _token);
    });

    test('URL แบบ path routing — เผื่อวันหลังเปลี่ยนไปใช้ usePathUrlStrategy()', () {
      pendingCheckin.readFromAppStart(
        url: Uri.parse('https://activity.tsu.ac.th/checkin?c=$_token'),
      );
      expect(pendingCheckin.token, _token);
    });

    test('เปิดหน้าแรกตามปกติ → ไม่มี token ค้าง', () {
      pendingCheckin.readFromAppStart(url: Uri.parse('https://activity.tsu.ac.th/#/'));
      expect(pendingCheckin.hasPending, isFalse);
      pendingCheckin.readFromAppStart(url: Uri.parse('https://activity.tsu.ac.th/'));
      expect(pendingCheckin.hasPending, isFalse);
    });

    test('route ที่ไม่มี token → ตกไปอ่าน URL ต่อจนได้', () {
      pendingCheckin.readFromAppStart(
        route: '/',
        url: Uri.parse('https://activity.tsu.ac.th/#/checkin?c=$_token'),
      );
      expect(pendingCheckin.token, _token);
    });

    test('ไม่มีทั้ง route และ URL ก็ไม่พัง', () {
      pendingCheckin.readFromAppStart();
      expect(pendingCheckin.hasPending, isFalse);
    });
  });

  group('หน้ายืนยันเช็กอิน', () {
    testWidgets('นิสิตเห็นการ์ดยืนยัน ไม่เช็กอินให้เองอัตโนมัติ', (tester) async {
      _loginAs('student');
      await _pumpConfirm(tester);

      expect(find.text('ยืนยันเช็กอินกิจกรรมนี้?'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'ยืนยันเช็กอิน'), findsOneWidget);
      // ต้องยังไม่มีผลลัพธ์ใด ๆ จนกว่าจะกดยืนยัน
      expect(find.text('เช็กอินสำเร็จ'), findsNothing);
    });

    testWidgets('การ์ดยืนยันบอกว่ากำลังเช็กอินในนามใคร', (tester) async {
      _loginAs('student');
      await _pumpConfirm(tester);
      expect(find.textContaining('650811001'), findsOneWidget);
    });

    testWidgets('ย้ำกฎ D2 ก่อนกดยืนยัน', (tester) async {
      _loginAs('student');
      await _pumpConfirm(tester);
      expect(
        find.textContaining('ชั่วโมงกิจกรรมจะนับให้เมื่อส่งหลักฐานและเจ้าหน้าที่อนุมัติแล้ว'),
        findsOneWidget,
      );
    });

    testWidgets('เจ้าหน้าที่/ผู้ดูแลเปิดลิงก์ → บอกว่าบัญชีนี้เช็กอินไม่ได้', (tester) async {
      for (final role in ['staff', 'admin']) {
        _loginAs(role);
        await _pumpConfirm(tester);

        expect(find.text('บัญชีนี้เช็กอินไม่ได้ (เฉพาะนิสิต)'), findsOneWidget);
        // ต้องไม่มีปุ่มยืนยันให้กดเลย (กันยิงคำขอที่ backend จะตอบ 403 อยู่ดี)
        expect(find.widgetWithText(FilledButton, 'ยืนยันเช็กอิน'), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'ออกจากระบบเพื่อสลับบัญชี'),
          findsOneWidget,
        );
      }
    });

    testWidgets('กด "ยังไม่เช็กอิน" → เรียก onDone เพื่อเคลียร์ token ที่ค้าง',
        (tester) async {
      _loginAs('student');
      var done = false;
      await _pumpConfirm(tester, onDone: () => done = true);

      await tester.tap(find.text('ยังไม่เช็กอิน กลับหน้าหลัก'));
      await tester.pump();

      expect(done, isTrue);
    });
  });

  group('หน้า login ตอนมี token ค้าง (F4b)', () {
    testWidgets('บอกเหตุผลว่าทำไมต้องล็อกอินก่อน และ token ไม่หาย', (tester) async {
      pendingCheckin.readFromAppStart(route: '/checkin?c=$_token');
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
      );

      expect(find.textContaining('เพื่อเช็กอินกิจกรรมที่สแกนมา'), findsOneWidget);
      // token ยังอยู่ครบหลังหน้า login วาดเสร็จ — เก็บไว้ในสถานะของแอป ไม่ได้
      // ผูกกับ URL ของหน้าที่ถูกแทนที่
      expect(pendingCheckin.token, _token);
    });

    testWidgets('เปิดแอปตามปกติ → หน้า login ไม่มีแบนเนอร์', (tester) async {
      pendingCheckin.readFromAppStart(route: '/');
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
      );

      expect(find.textContaining('เพื่อเช็กอินกิจกรรมที่สแกนมา'), findsNothing);
    });
  });
}
