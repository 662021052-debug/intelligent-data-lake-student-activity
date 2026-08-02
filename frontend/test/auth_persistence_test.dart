// FIX_Persist_Login_On_Refresh — JWT ต้องอยู่ข้ามการรีเฟรชหน้า
//
// Flutter web โหลดแอปใหม่ทั้งก้อนทุกครั้งที่กดรีเฟรช ตัวแปรใน memory จึงหายหมด
// เทสต์ชุดนี้จำลอง "รีเฟรช" ด้วยการล้าง state ในหน่วยความจำ (logout ทิ้ง) แล้ว
// เรียก restore() ใหม่จาก storage เดิม เหมือนที่ main() ทำตอนแอปเปิด
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:activity_tracking_frontend/main.dart';
import 'package:activity_tracking_frontend/screens/checkin_confirm_screen.dart';
import 'package:activity_tracking_frontend/screens/home_screen.dart';
import 'package:activity_tracking_frontend/screens/login_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/services/pending_checkin.dart';

const _checkinToken = 'b97e85b0dd544be29d3b73063bfb5883';

/// JWT รูปแบบเดียวกับที่ backend ออกให้: payload มี sub / role / exp
String _makeJwt({
  String sub = '650811001',
  String role = 'student',
  Duration expiresIn = const Duration(hours: 1),
  bool withExp = true,
}) {
  String seg(Map<String, dynamic> map) =>
      base64Url.encode(utf8.encode(jsonEncode(map))).replaceAll('=', '');

  final payload = <String, dynamic>{
    'sub': sub,
    'role': role,
    if (withExp)
      'exp': DateTime.now().toUtc().add(expiresIn).millisecondsSinceEpoch ~/ 1000,
  };
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.not-a-real-signature';
}

/// จำลองการรีเฟรชหน้า: state ในหน่วยความจำหายไป แต่ storage ยังอยู่
Future<void> _reload() async {
  authService.token = null;
  authService.username = null;
  authService.role = null;
  await authService.restore();
}

Future<String?> _savedToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(authTokenKey);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    authService.token = null;
    authService.username = null;
    authService.role = null;
    pendingCheckin.clear();
  });

  group('กู้สถานะล็อกอินจาก storage', () {
    test('มี token ที่ยังไม่หมดอายุ → ยังล็อกอินอยู่หลังรีเฟรช', () async {
      SharedPreferences.setMockInitialValues({
        authTokenKey: _makeJwt(sub: '650811001', role: 'student'),
      });

      await _reload();

      expect(authService.isLoggedIn, isTrue);
      expect(authService.username, '650811001');
      expect(authService.role, 'student');
    });

    test('กู้ role มาครบ สิทธิ์จึงไม่เพี้ยนหลังรีเฟรช', () async {
      SharedPreferences.setMockInitialValues({
        authTokenKey: _makeJwt(sub: 'admin', role: 'admin'),
      });

      await _reload();

      expect(authService.isAdmin, isTrue);
      expect(authService.canWrite, isTrue);
    });

    test('ไม่มี token เก็บไว้ → ไปหน้า login ตามเดิม', () async {
      await _reload();
      expect(authService.isLoggedIn, isFalse);
    });

    test('token หมดอายุ → ไม่กู้ และลบทิ้งไม่ให้ค้าง', () async {
      SharedPreferences.setMockInitialValues({
        authTokenKey: _makeJwt(expiresIn: const Duration(hours: -1)),
      });

      await _reload();

      expect(authService.isLoggedIn, isFalse);
      expect(await _savedToken(), isNull);
    });

    test('token พังจนถอดไม่ออก → ไม่กู้ ไม่ล้ม และลบทิ้ง', () async {
      SharedPreferences.setMockInitialValues({authTokenKey: 'ขยะ.ไม่ใช่.jwt'});

      await _reload();

      expect(authService.isLoggedIn, isFalse);
      expect(await _savedToken(), isNull);
    });

    test('token ที่ไม่มี exp → ยังกู้ให้ ปล่อย backend เป็นคนตัดสินตอนยิงจริง', () async {
      SharedPreferences.setMockInitialValues({authTokenKey: _makeJwt(withExp: false)});

      await _reload();

      expect(authService.isLoggedIn, isTrue);
    });
  });

  group('ล้าง token ที่ใช้ไม่ได้', () {
    test('logout ลบ token ออกจาก storage ด้วย', () async {
      SharedPreferences.setMockInitialValues({authTokenKey: _makeJwt()});
      await _reload();
      expect(authService.isLoggedIn, isTrue);

      authService.logout();
      await Future<void>.delayed(Duration.zero); // logout ลบแบบ fire-and-forget

      expect(authService.isLoggedIn, isFalse);
      expect(await _savedToken(), isNull);
    });

    test('logout แล้วรีเฟรช → ไม่หลุดกลับเข้าระบบเอง', () async {
      SharedPreferences.setMockInitialValues({authTokenKey: _makeJwt()});
      await _reload();

      authService.logout();
      await Future<void>.delayed(Duration.zero);
      await _reload();

      expect(authService.isLoggedIn, isFalse);
    });

    test('backend ตอบ 401 → เคลียร์ทั้ง state และ storage', () async {
      SharedPreferences.setMockInitialValues({authTokenKey: _makeJwt()});
      await _reload();

      authService.handleUnauthorized();
      await Future<void>.delayed(Duration.zero);

      expect(authService.isLoggedIn, isFalse);
      expect(await _savedToken(), isNull);
    });

    test('401 ตอนที่ยังไม่ได้ล็อกอิน → ไม่ทำอะไร (ไม่วนเด้ง)', () async {
      var notified = 0;
      void listener() => notified++;
      authService.addListener(listener);

      authService.handleUnauthorized();

      authService.removeListener(listener);
      expect(notified, 0);
    });
  });

  group('หน้าที่แอปเปิดหลังรีเฟรช', () {
    testWidgets('ล็อกอินอยู่ → เข้าหน้าหลักเลย ไม่เด้งไป login', (tester) async {
      SharedPreferences.setMockInitialValues({
        authTokenKey: _makeJwt(sub: '650811001', role: 'student'),
      });
      await _reload();

      await tester.pumpWidget(const MyApp());
      await tester.pump();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('ไม่มี token → อยู่หน้า login', (tester) async {
      await _reload();

      await tester.pumpWidget(const MyApp());
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('deep link เช็กอิน + ล็อกอินค้างอยู่ → รีเฟรชแล้วยังเช็กอินต่อได้',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        authTokenKey: _makeJwt(sub: '650811001', role: 'student'),
      });
      await _reload();
      // รีเฟรชที่ URL ของลิงก์เช็กอิน — main() อ่าน route ใหม่ทุกครั้งที่แอปเปิด
      pendingCheckin.readFromAppStart(route: '/checkin?c=$_checkinToken');

      await tester.pumpWidget(const MyApp());
      await tester.pump();

      expect(find.byType(CheckinConfirmScreen), findsOneWidget);
      expect(find.text('ยืนยันเช็กอินกิจกรรมนี้?'), findsOneWidget);
    });

    testWidgets('deep link แต่ยังไม่ล็อกอิน → หน้า login และ token ไม่หาย',
        (tester) async {
      await _reload();
      pendingCheckin.readFromAppStart(route: '/checkin?c=$_checkinToken');

      await tester.pumpWidget(const MyApp());
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(pendingCheckin.token, _checkinToken);
    });
  });
}
