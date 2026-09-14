/// ข้อมูล QR เช็กอินประจำกิจกรรม (`GET /activities/{id}/checkin-qr`)
///
/// เจ้าหน้าที่เจ้าของกิจกรรม/ผู้ดูแลเท่านั้นที่ขอได้ — token ไม่ได้อยู่ใน
/// `ActivityRead` จึงไม่หลุดไปถึงนิสิตผ่านรายการกิจกรรมปกติ
class CheckinQr {
  final int activityId;
  final String activityName;

  /// รหัสประจำกิจกรรม — ใช้กรอกมือได้เมื่อกล้องนิสิตใช้ไม่ได้
  final String token;

  /// URL ที่เอาไปสร้างภาพ QR (`https://<โดเมน>/#/checkin?c=<token>`)
  ///
  /// เก็บ URL เต็มเพื่อให้กล้องมือถือปกติขึ้นปุ่ม "เปิดลิงก์" ให้ นิสิตจึงสแกน
  /// ได้โดยไม่ต้องเปิดแอปเข้าหน้าสแกนก่อน
  final String qrPayload;

  final DateTime startAt;
  final DateTime checkinOpensAt;
  final DateTime checkinClosesAt;

  CheckinQr({
    required this.activityId,
    required this.activityName,
    required this.token,
    required this.qrPayload,
    required this.startAt,
    required this.checkinOpensAt,
    required this.checkinClosesAt,
  });

  factory CheckinQr.fromJson(Map<String, dynamic> json) => CheckinQr(
        activityId: json['activity_id'] as int,
        activityName: json['activity_name'] as String,
        token: json['token'] as String,
        qrPayload: json['qr_payload'] as String,
        startAt: DateTime.parse(json['start_at'] as String),
        checkinOpensAt: DateTime.parse(json['checkin_opens_at'] as String),
        checkinClosesAt: DateTime.parse(json['checkin_closes_at'] as String),
      );

  /// ตอนนี้อยู่ในช่วงที่นิสิตสแกนได้จริงหรือยัง
  ///
  /// `start_at` และช่วงเช็กอินเป็น "เวลาไทยแบบไม่มีโซน" (ดู backend/app/timeutil.py)
  /// [nowTh] จึงต้องมาจาก `thaiNowNaive()` — เดิมเทียบเป็น UTC ป้ายสถานะเลยเพี้ยน 7 ชม.
  bool isOpenAt(DateTime nowTh) {
    final now = _naive(nowTh);
    return !now.isBefore(_naive(checkinOpensAt)) && !now.isAfter(_naive(checkinClosesAt));
  }

  /// ยังไม่ถึงเวลาเปิดเช็กอิน (ต่างจาก "เลยเวลาแล้ว" ซึ่งก็ปิดเหมือนกัน)
  bool isBeforeOpenAt(DateTime nowTh) => _naive(nowTh).isBefore(_naive(checkinOpensAt));

  /// เทียบด้วยตัวเลขวัน-เวลาล้วน ไม่ให้ธงโซนเวลาของ DateTime มาทำให้เลื่อน
  static DateTime _naive(DateTime value) => value.isUtc
      ? DateTime(
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
        )
      : value;
}
