import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// คีย์ที่เก็บ JWT ไว้ใน storage ของเบราว์เซอร์ (บนเว็บ shared_preferences
/// map ลง localStorage)
const String authTokenKey = 'auth_token';

class AuthService extends ChangeNotifier {
  String? token;
  String? username;
  String? role;

  bool get isLoggedIn => token != null;
  bool get canWrite => role == 'staff' || role == 'admin';
  bool get isAdmin => role == 'admin';

  /// กู้สถานะล็อกอินจาก token ที่เซฟไว้ ตอนแอปเริ่มทำงาน
  ///
  /// Flutter web โหลดแอปใหม่ทั้งก้อนทุกครั้งที่รีเฟรช ตัวแปรใน memory จึงหายหมด
  /// — ถ้าไม่กู้ตรงนี้ ผู้ใช้จะถูกเด้งไปหน้า login ทุกครั้งที่กด F5
  ///
  /// ตัว token พก `sub` กับ `role` มาอยู่แล้ว จึงตั้ง state ได้ครบโดยไม่ต้อง
  /// ยิง API ถาม และเช็ก `exp` ตั้งแต่ตอนนี้เลย เพื่อไม่ให้แอปเปิดเข้าไปด้วย
  /// token ที่หมดอายุแล้วค้างอยู่จนไปเจอ 401 กลางทาง
  Future<void> restore() async {
    final prefs = await _prefs();
    final saved = prefs?.getString(authTokenKey);
    if (saved == null || saved.isEmpty) return;

    final payload = _decodeJwtPayload(saved);
    if (payload.isEmpty || _isExpired(payload)) {
      await prefs?.remove(authTokenKey);
      return;
    }

    token = saved;
    username = payload['sub'] as String?;
    role = payload['role'] as String?;
    notifyListeners();
  }

  Future<void> login(String usernameInput, String password) async {
    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/auth/login'),
      body: {'username': usernameInput, 'password': password},
    );

    if (response.statusCode != 200) {
      throw Exception(_extractDetail(response) ?? 'เข้าสู่ระบบไม่สำเร็จ');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final newToken = data['access_token'] as String;
    final payload = _decodeJwtPayload(newToken);

    token = newToken;
    username = payload['sub'] as String?;
    role = payload['role'] as String?;

    // เซฟไม่สำเร็จก็ยังถือว่าล็อกอินสำเร็จ — แค่เสีย "จำไว้ข้ามรีเฟรช" ไป
    // ไม่ใช่เหตุให้ผู้ใช้เข้าระบบไม่ได้
    await (await _prefs())?.setString(authTokenKey, newToken);

    notifyListeners();
  }

  void logout() {
    token = null;
    username = null;
    role = null;
    // ลบของที่เซฟไว้ด้วย ไม่งั้นรีเฟรชแล้วเด้งกลับเข้าระบบเองทั้งที่กดออกไปแล้ว
    // ทำแบบ fire-and-forget เพื่อให้ logout() ยังเรียกจาก onPressed ตรง ๆ ได้
    unawaited(_clearSavedToken());
    notifyListeners();
  }

  /// backend ตอบ 401 (token หมดอายุ / ถูกเพิกถอน) — ทิ้ง token ที่ใช้ไม่ได้แล้ว
  /// เพื่อให้แอปเด้งไปหน้า login แทนที่จะวนเจอ error เดิมทุกหน้า
  void handleUnauthorized() {
    if (!isLoggedIn) return;
    logout();
  }

  Future<void> _clearSavedToken() async {
    await (await _prefs())?.remove(authTokenKey);
  }

  /// storage ของเบราว์เซอร์ — คืน null เมื่อใช้ไม่ได้ (โหมดส่วนตัว, ผู้ใช้ปิด
  /// storage, หรือรันในเทสต์ที่ไม่ได้ตั้ง mock)
  ///
  /// การจำล็อกอินเป็นของแถม ไม่ใช่เงื่อนไขของการล็อกอิน — ถ้า storage ล่ม
  /// แอปต้องยังใช้งานได้ตามปกติในเซสชันนั้น ไม่ใช่พังทั้งระบบ
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static bool _isExpired(Map<String, dynamic> payload) {
    final exp = payload['exp'];
    if (exp is! int) return false; // ไม่มี exp = ให้ backend เป็นคนตัดสินตอนยิงจริง
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    return !expiresAt.isAfter(DateTime.now().toUtc());
  }

  String? _extractDetail(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      return body['detail']?.toString();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _decodeJwtPayload(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return {};
      final normalized = base64Url.normalize(parts[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      // token ที่พังจนถอดไม่ออก ถือว่าใช้ไม่ได้ ไม่ใช่เหตุให้แอปล้ม
      return {};
    }
  }
}

final authService = AuthService();
