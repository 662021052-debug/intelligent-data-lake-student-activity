/// ข้อมูล QR เช็กอินประจำกิจกรรม (`GET /activities/{id}/checkin-qr`)
///
/// เจ้าหน้าที่เจ้าของกิจกรรม/ผู้ดูแลเท่านั้นที่ขอได้ — token ไม่ได้อยู่ใน
/// `ActivityRead` จึงไม่หลุดไปถึงนิสิตผ่านรายการกิจกรรมปกติ
class CheckinQr {
  final int activityId;
  final String activityName;

  /// รหัสประจำกิจกรรม — ใช้กรอกมือได้เมื่อกล้องนิสิตใช้ไม่ได้
  final String token;

  /// ข้อความที่เอาไปสร้างภาพ QR (`TSU-CHECKIN:<token>`)
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
  /// เทียบเป็น UTC เพราะ backend ส่งเวลามาแบบไม่มีโซน (`datetime.utcnow()`)
  bool isOpenAt(DateTime nowUtc) =>
      !nowUtc.isBefore(_asUtc(checkinOpensAt)) && !nowUtc.isAfter(_asUtc(checkinClosesAt));

  /// ยังไม่ถึงเวลาเปิดเช็กอิน (ต่างจาก "เลยเวลาแล้ว" ซึ่งก็ปิดเหมือนกัน)
  bool isBeforeOpenAt(DateTime nowUtc) => nowUtc.isBefore(_asUtc(checkinOpensAt));

  static DateTime _asUtc(DateTime value) => value.isUtc
      ? value
      : DateTime.utc(
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
        );
}
