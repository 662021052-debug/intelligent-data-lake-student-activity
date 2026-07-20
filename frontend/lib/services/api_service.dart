import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/page.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

class ApiService {
  static Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  static Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (authService.token != null) 'Authorization': 'Bearer ${authService.token}',
      };

  static dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    String message = 'เกิดข้อผิดพลาด (${response.statusCode})';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] != null) {
        message = body['detail'].toString();
      }
    } catch (_) {
      // ignore, keep default message
    }
    throw ApiException(response.statusCode, message);
  }

  static Future<Page<T>> fetchPage<T>(
    String path,
    T Function(Map<String, dynamic>) fromJsonT, {
    Map<String, String>? query,
  }) async {
    final response = await http.get(_uri(path, query), headers: _headers());
    final data = _decode(response) as Map<String, dynamic>;
    return Page<T>.fromJson(data, fromJsonT);
  }

  static Future<List<T>> fetchList<T>(
    String path,
    T Function(Map<String, dynamic>) fromJsonT, {
    Map<String, String>? query,
  }) async {
    final response = await http.get(_uri(path, query), headers: _headers());
    final data = _decode(response) as List;
    return data.map((e) => fromJsonT(e as Map<String, dynamic>)).toList();
  }

  static Future<T> create<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJsonT,
  ) async {
    final response = await http.post(_uri(path), headers: _headers(), body: jsonEncode(body));
    final data = _decode(response) as Map<String, dynamic>;
    return fromJsonT(data);
  }

  static Future<T> update<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJsonT,
  ) async {
    final response = await http.put(_uri(path), headers: _headers(), body: jsonEncode(body));
    final data = _decode(response) as Map<String, dynamic>;
    return fromJsonT(data);
  }

  static Future<void> delete(String path) async {
    final response = await http.delete(_uri(path), headers: _headers());
    _decode(response);
  }

  static Future<T> patch<T>(
    String path,
    T Function(Map<String, dynamic>) fromJsonT,
  ) async {
    final response = await http.patch(_uri(path), headers: _headers());
    final data = _decode(response) as Map<String, dynamic>;
    return fromJsonT(data);
  }
}
