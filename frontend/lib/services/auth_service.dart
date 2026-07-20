import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class AuthService extends ChangeNotifier {
  String? token;
  String? username;
  String? role;

  bool get isLoggedIn => token != null;
  bool get canWrite => role == 'staff' || role == 'admin';
  bool get isAdmin => role == 'admin';

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
    notifyListeners();
  }

  void logout() {
    token = null;
    username = null;
    role = null;
    notifyListeners();
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
    final parts = jwt.split('.');
    if (parts.length != 3) return {};
    final normalized = base64Url.normalize(parts[1]);
    final payload = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(payload) as Map<String, dynamic>;
  }
}

final authService = AuthService();
