import 'package:flutter/foundation.dart';

/// path ของหน้ายืนยันเช็กอิน — ต้องตรงกับ `CHECKIN_PATH` ฝั่ง backend
/// (`app/checkin.py`) ที่ใส่ลงใน QR
const String checkinRoutePath = '/checkin';

/// ชื่อพารามิเตอร์ที่พา token มากับลิงก์ — ตรงกับ `CHECKIN_QUERY_KEY` ฝั่ง backend
const String checkinTokenParam = 'c';

/// token ที่ค้างรอเช็กอินอยู่ จากการเปิดลิงก์ใน QR ด้วยกล้องมือถือปกติ (F4)
///
/// เก็บไว้เป็น "สถานะของแอป" แทนที่จะส่งต่อเป็น query param ระหว่างหน้า เพราะ
/// นิสิตที่ยังไม่ได้ล็อกอินจะถูกพาไปหน้า login ก่อน — ถ้า token ผูกอยู่กับ URL
/// ของหน้าที่ถูกแทนที่ ก็หายไปพร้อมกัน แต่ถ้าอยู่ตรงนี้ พอล็อกอินเสร็จแอปจะ
/// พากลับมาหน้ายืนยันเช็กอินได้เอง โดยหน้า login ไม่ต้องรู้จัก deep link เลย
class PendingCheckin extends ChangeNotifier {
  String? _token;

  String? get token => _token;
  bool get hasPending => _token != null;

  /// อ่าน token ตอนแอปเริ่มทำงาน จาก route ที่ถูกเปิดมา และ/หรือ URL ของหน้า
  ///
  /// ดูสองที่เพราะมีสองกลไกที่พา token มาได้ แล้วแต่ url strategy ที่ Flutter ใช้:
  /// - [route] = `defaultRouteName` ซึ่งเป็น `/checkin?c=x` เมื่อใช้ hash routing
  /// - [url] = URL เต็มของหน้า (`Uri.base`) ซึ่งมี `#/checkin?c=x` อยู่ใน fragment
  ///
  /// อ่านทั้งคู่แล้วเอาอันที่ได้ก่อน จะได้ไม่พังถ้าวันหลังเปลี่ยนไปใช้
  /// `usePathUrlStrategy()` หรือ Flutter เปลี่ยนวิธีรายงาน route
  void readFromAppStart({String? route, Uri? url}) {
    _token = _tokenFromRoute(route) ?? _tokenFromUrl(url);
    notifyListeners();
  }

  /// เคลียร์เมื่อเช็กอินเสร็จ (หรือผู้ใช้กดออก) เพื่อให้แอปกลับไปหน้าหลักตามปกติ
  void clear() {
    if (_token == null) return;
    _token = null;
    notifyListeners();
  }

  /// ดึง token จาก URL เต็มของหน้า — ทั้งแบบ hash (`.../#/checkin?c=x`) และ
  /// แบบ path (`.../checkin?c=x`)
  static String? _tokenFromUrl(Uri? url) {
    if (url == null) return null;
    if (url.fragment.isNotEmpty) {
      final fragment = url.fragment.startsWith('/') ? url.fragment : '/${url.fragment}';
      final fromFragment = _tokenFromRoute(fragment);
      if (fromFragment != null) return fromFragment;
    }
    return _tokenFromRoute('${url.path}?${url.query}');
  }

  static String? _tokenFromRoute(String? route) {
    if (route == null || route.isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(route);
    } on FormatException {
      return null;
    }
    // ยอมรับทั้ง `/checkin` และ `/checkin/` — ลิงก์ที่คนพิมพ์เองมักมี slash ท้าย
    final path = uri.path.endsWith('/') && uri.path.length > 1
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    if (path != checkinRoutePath) return null;

    final token = uri.queryParameters[checkinTokenParam]?.trim();
    return (token == null || token.isEmpty) ? null : token;
  }
}

final pendingCheckin = PendingCheckin();
