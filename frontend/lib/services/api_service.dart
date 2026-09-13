import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';
import '../models/activity_import.dart';
import '../models/chat_response.dart';
import '../models/checkin_qr.dart';
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
  /// เพดาน `limit` ของทุก endpoint แบบแบ่งหน้าใน backend (`Query(..., le=200)`)
  ///
  /// ขอเกินนี้ backend ตอบ 422 ทั้งคำขอ — หน้าจอที่ไม่ได้โชว์ error จะว่างเปล่าเงียบ ๆ
  /// (เคสจริง: dropdown เลือกนิสิตขอ limit=500 แล้วไม่มีรายชื่อให้เลือกเลย)
  static const int maxPageSize = 200;

  /// บีบ `limit` ที่เกินเพดานลงมาให้พอดี เพื่อไม่ให้พลาดแบบเดิมซ้ำอีก
  ///
  /// เป็นตาข่ายกันพลาดชั้นสุดท้าย ไม่ใช่ที่แก้หลัก — ผู้เรียกที่ต้องการ "ทุกรายการ"
  /// ควรใช้ [fetchAll] ซึ่งไล่ดึงทีละหน้าจนครบ ไม่ใช่ขอก้อนใหญ่ครั้งเดียวแล้วโดนตัด
  ///
  /// เปิดเป็น public เพราะเป็นฟังก์ชันบริสุทธิ์ที่เทสต์ตรง ๆ ได้ (ApiService เรียก
  /// `http.get` ตรง จึงไม่มีจุดให้สวม mock client โดยไม่รื้อโครงทั้งคลาส)
  static Map<String, String>? clampLimit(Map<String, String>? query) {
    if (query == null) return null;
    final raw = query['limit'];
    if (raw == null) return query;
    final value = int.tryParse(raw);
    if (value == null || value <= maxPageSize) return query;
    return {...query, 'limit': '$maxPageSize'};
  }

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
    if (response.statusCode == 401) {
      // token หมดอายุ/ถูกเพิกถอน — ทิ้งทั้งใน state และใน storage แล้วปล่อยให้
      // ตัว builder ที่ main.dart พาไปหน้า login แทนที่จะค้าง error เดิมทุกหน้า
      authService.handleUnauthorized();
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
    final response = await http.get(_uri(path, clampLimit(query)), headers: _headers());
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
    int pageSize = maxPageSize,
    int maxItems = 2000,
  }) async {
    final size = pageSize.clamp(1, maxPageSize);
    final items = <T>[];
    var skip = 0;
    while (true) {
      final page = await fetchPage<T>(
        path,
        fromJsonT,
        query: {...?query, 'skip': '$skip', 'limit': '$size'},
      );
      items.addAll(page.items);
      skip += size;
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
    final response = await http.get(_uri(path, clampLimit(query)), headers: _headers());
    final data = _decode(response) as List;
    return data.map((e) => fromJsonT(e as Map<String, dynamic>)).toList();
  }

  /// รายการสตริงล้วน เช่น `GET /faculties` ที่คืน `["คณะ ก", "คณะ ข"]`
  static Future<List<String>> fetchStringList(String path) async {
    final response = await http.get(_uri(path, null), headers: _headers());
    final data = _decode(response) as List;
    return data.map((e) => e as String).toList();
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

  /// นำเข้าแผนการจัดกิจกรรมทั้งภาคเรียนจากไฟล์ .xlsx/.csv (ข้อ 6.7)
  ///
  /// 200 ไม่ได้แปลว่าทุกแถวผ่าน — ผลลัพธ์บอกว่าสำเร็จกี่แถวและผิดแถวไหนบ้าง
  /// ส่วน 400 คือไฟล์ใช้ไม่ได้ทั้งไฟล์ (นามสกุลผิด/ไม่มีหัวตาราง) ซึ่งโยนเป็น
  /// [ApiException] ตามปกติ
  static Future<ActivityImportResult> importActivities(
    Uint8List bytes,
    String filename,
  ) async {
    final request = http.MultipartRequest('POST', _uri('/activities/import'));
    if (authService.token != null) {
      request.headers['Authorization'] = 'Bearer ${authService.token}';
    }
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decode(response) as Map<String, dynamic>;
    return ActivityImportResult.fromJson(data);
  }

  /// ข้อมูล QR เช็กอินของกิจกรรม สำหรับเจ้าหน้าที่เจ้าของกิจกรรม/ผู้ดูแล
  static Future<CheckinQr> fetchCheckinQr(int activityId) async {
    return fetchObject('/activities/$activityId/checkin-qr', CheckinQr.fromJson);
  }

  /// เช็กอินหน้างานด้วย token ที่สแกนได้จาก QR ของกิจกรรม
  ///
  /// ตัวตนผู้เช็กอินมาจาก JWT ล้วน ๆ — ฝั่งแอปส่งได้แค่ token เท่านั้น
  ///
  /// ส่งค่าที่สแกน/กรอกมาดิบ ๆ ได้เลย backend รับได้ทั้ง URL เต็มจาก QR
  /// (`.../#/checkin?c=<token>`), รูปแบบเก่า `TSU-CHECKIN:<token>` และ token เปล่า
  static Future<Participation> checkin(String token) async {
    return create('/participations/checkin', {'token': token}, Participation.fromJson);
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

  /// ดึงไฟล์ (เช่น รายงาน Excel/PDF) มาเป็น bytes พร้อมแนบ JWT
  ///
  /// ใช้ `http.get` ตรงเหมือน [fetchEvidence] เพราะ body ไม่ใช่ JSON — แต่ error
  /// ยังผ่าน [_decode] เพื่อให้ได้ข้อความไทยชุดเดียวกับที่เหลือทั้งแอป
  static Future<Uint8List> downloadBytes(String path, {Map<String, String>? query}) async {
    final response = await http.get(
      _uri(path, query),
      headers: {
        if (authService.token != null) 'Authorization': 'Bearer ${authService.token}',
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    _decode(response); // throws ApiException with the server detail
    throw ApiException(response.statusCode, 'unreachable');
  }
}
