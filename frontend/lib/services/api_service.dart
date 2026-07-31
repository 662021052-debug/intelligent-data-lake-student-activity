import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';
import '../models/chat_response.dart';
import '../models/ocr_result.dart';
import '../models/page.dart';
import '../models/participation.dart';
import '../utils/api_error.dart';
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
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      // body ไม่ใช่ JSON (เช่น HTML ของ proxy) — ปล่อยให้ตัวแปลงใช้รหัสสถานะแทน
    }
    // แปลงเป็นข้อความไทยที่ตรงนี้ที่เดียว ทุกหน้าจึงไม่เห็น JSON ดิบของ Pydantic
    throw ApiException(response.statusCode, apiErrorMessage(response.statusCode, body));
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

  /// ดึงทุกหน้าของ endpoint แบบแบ่งหน้า จนครบ `total`
  ///
  /// ใช้กับข้อมูลที่ต้องมี "ครบทุกรายการ" จริง ๆ เช่น dropdown เลือกนิสิต/กิจกรรม
  /// (เดิมยิงขอ `limit=500` ครั้งเดียวซึ่งเกินเพดาน 200 ของ backend แล้วได้ 422)
  /// [maxItems] กันไม่ให้ไล่ดึงไม่รู้จบถ้าข้อมูลโตมาก
  static Future<List<T>> fetchAll<T>(
    String path,
    T Function(Map<String, dynamic>) fromJsonT, {
    Map<String, String>? query,
    int pageSize = 200,
    int maxItems = 2000,
  }) async {
    final items = <T>[];
    var skip = 0;
    while (true) {
      final page = await fetchPage<T>(
        path,
        fromJsonT,
        query: {...?query, 'skip': '$skip', 'limit': '$pageSize'},
      );
      items.addAll(page.items);
      skip += pageSize;
      if (page.items.isEmpty || items.length >= page.total || items.length >= maxItems) {
        return items;
      }
    }
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

  static Future<T> fetchObject<T>(
    String path,
    T Function(Map<String, dynamic>) fromJsonT, {
    Map<String, String>? query,
  }) async {
    final response = await http.get(_uri(path, query), headers: _headers());
    final data = _decode(response) as Map<String, dynamic>;
    return fromJsonT(data);
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

  /// Uploads an evidence file (image/PDF) for a participation via multipart/form-data.
  static Future<Participation> uploadEvidence(
    int participationId,
    Uint8List bytes,
    String filename,
    String contentType,
  ) async {
    final request =
        http.MultipartRequest('POST', _uri('/participations/$participationId/evidence'));
    if (authService.token != null) {
      request.headers['Authorization'] = 'Bearer ${authService.token}';
    }
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType.parse(contentType),
    ));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decode(response) as Map<String, dynamic>;
    return Participation.fromJson(data);
  }

  /// Runs (or re-runs) the Silver OCR pipeline for a participation's evidence.
  static Future<OcrResult> processEvidence(int participationId) async {
    final response = await http.post(
      _uri('/participations/$participationId/evidence/process'),
      headers: _headers(),
    );
    final data = _decode(response) as Map<String, dynamic>;
    return OcrResult.fromJson(data);
  }

  /// Latest OCR result for a participation, or null if none has been produced.
  static Future<OcrResult?> fetchOcrResult(int participationId) async {
    try {
      return await fetchObject('/participations/$participationId/ocr', OcrResult.fromJson);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Asks the student chatbot a Thai-language question (Phase 16–18).
  static Future<ChatResponse> askChatbot(String question) async {
    return create('/chatbot/ask', {'question': question}, ChatResponse.fromJson);
  }

  /// Fetches the latest evidence file for a participation as (bytes, contentType).
  static Future<(Uint8List, String)> fetchEvidence(int participationId) async {
    final response = await http.get(
      _uri('/participations/$participationId/evidence'),
      headers: {
        if (authService.token != null) 'Authorization': 'Bearer ${authService.token}',
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final contentType = response.headers['content-type'] ?? 'application/octet-stream';
      return (response.bodyBytes, contentType);
    }
    _decode(response); // throws ApiException with the server detail
    throw ApiException(response.statusCode, 'unreachable');
  }
}
