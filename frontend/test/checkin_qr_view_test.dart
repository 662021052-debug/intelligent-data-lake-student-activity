// F2 — จอ QR เช็กอินที่เจ้าหน้าที่ฉายหน้างาน
//
// ทดสอบ CheckinQrView ตรง ๆ (ไม่ผ่าน CheckinQrScreen ที่ต้องยิง API) จึงคุม
// เวลา "ตอนนี้" ได้ แล้วตรวจป้ายสถานะทั้งสามแบบโดยไม่ต้องรอเวลาจริง
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:activity_tracking_frontend/models/checkin_qr.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/checkin_qr_view.dart';

/// payload ที่ backend ส่งมาจริง — เวลาเป็น UTC แบบไม่มีโซน
Map<String, dynamic> _payload() => {
      'activity_id': 29,
      'activity_name': 'จิตอาสาพัฒนามหาวิทยาลัย (กำลังจัดอยู่ตอนนี้)',
      'token': 'b97e85b0dd544be29d3b73063bfb5883',
      'qr_payload': 'https://activity.tsu.ac.th/#/checkin?c=b97e85b0dd544be29d3b73063bfb5883',
      'start_at': '2026-08-02T08:47:00',
      'checkin_opens_at': '2026-08-02T07:47:00',
      'checkin_closes_at': '2026-08-02T14:47:00',
    };

Future<void> _pumpView(WidgetTester tester, {required DateTime nowUtc}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: CheckinQrView(qr: CheckinQr.fromJson(_payload()), now: nowUtc),
      ),
    ),
  );
}

void main() {
  group('CheckinQr', () {
    test('อ่าน payload จาก backend ครบทุกฟิลด์', () {
      final qr = CheckinQr.fromJson(_payload());
      expect(qr.activityId, 29);
      expect(qr.token, 'b97e85b0dd544be29d3b73063bfb5883');
      // QR เก็บ URL เต็ม กล้องมือถือปกติจึงขึ้นปุ่มเปิดลิงก์ให้ (F4/B3)
      expect(qr.qrPayload, 'https://activity.tsu.ac.th/#/checkin?c=${qr.token}');
    });

    test('ช่วงเวลาเช็กอินคิดเป็น UTC ตรงกับที่ backend บังคับ', () {
      final qr = CheckinQr.fromJson(_payload());

      expect(qr.isOpenAt(DateTime.utc(2026, 8, 2, 9, 0)), isTrue);
      expect(qr.isBeforeOpenAt(DateTime.utc(2026, 8, 2, 9, 0)), isFalse);

      // ก่อนเปิด 1 นาที และหลังปิด 1 นาที ต้องถือว่าปิด
      expect(qr.isOpenAt(DateTime.utc(2026, 8, 2, 7, 46)), isFalse);
      expect(qr.isBeforeOpenAt(DateTime.utc(2026, 8, 2, 7, 46)), isTrue);
      expect(qr.isOpenAt(DateTime.utc(2026, 8, 2, 14, 48)), isFalse);
      expect(qr.isBeforeOpenAt(DateTime.utc(2026, 8, 2, 14, 48)), isFalse);

      // ขอบพอดีทั้งสองด้านยังเช็กอินได้
      expect(qr.isOpenAt(DateTime.utc(2026, 8, 2, 7, 47)), isTrue);
      expect(qr.isOpenAt(DateTime.utc(2026, 8, 2, 14, 47)), isTrue);
    });
  });

  testWidgets('แสดง QR ที่สร้างจาก payload ของกิจกรรม (ไม่ใช่ token เปล่า)', (tester) async {
    await _pumpView(tester, nowUtc: DateTime.utc(2026, 8, 2, 9, 0));

    expect(find.byType(QrImageView), findsOneWidget);
    // QrImageView ไม่เปิด data ให้อ่าน จึงผูก payload ไว้เป็น key ของภาพ
    expect(
      find.byKey(const ValueKey(
          'https://activity.tsu.ac.th/#/checkin?c=b97e85b0dd544be29d3b73063bfb5883')),
      findsOneWidget,
    );
  });

  testWidgets('แสดงรหัสสำรองไว้ให้กรอกมือเมื่อกล้องใช้ไม่ได้', (tester) async {
    await _pumpView(tester, nowUtc: DateTime.utc(2026, 8, 2, 9, 0));

    expect(find.text('b97e85b0dd544be29d3b73063bfb5883'), findsOneWidget);
    expect(find.textContaining('กล้องใช้ไม่ได้?'), findsOneWidget);
  });

  testWidgets('อยู่ในช่วงเวลา → ป้าย "เปิดให้เช็กอินแล้ว"', (tester) async {
    await _pumpView(tester, nowUtc: DateTime.utc(2026, 8, 2, 9, 0));
    expect(find.text('เปิดให้เช็กอินแล้ว'), findsOneWidget);
  });

  testWidgets('ก่อนเวลา → ป้าย "ยังไม่ถึงเวลาเช็กอิน"', (tester) async {
    await _pumpView(tester, nowUtc: DateTime.utc(2026, 8, 2, 6, 0));
    expect(find.text('ยังไม่ถึงเวลาเช็กอิน'), findsOneWidget);
  });

  testWidgets('เลยเวลา → ป้าย "เลยเวลาเช็กอินแล้ว"', (tester) async {
    await _pumpView(tester, nowUtc: DateTime.utc(2026, 8, 2, 20, 0));
    expect(find.text('เลยเวลาเช็กอินแล้ว'), findsOneWidget);
  });

  testWidgets('ย้ำกฎ D2 บนจอด้วย: เช็กอินไม่ใช่ชั่วโมง', (tester) async {
    await _pumpView(tester, nowUtc: DateTime.utc(2026, 8, 2, 9, 0));
    expect(find.textContaining('ชั่วโมงยังต้องให้นิสิตส่งหลักฐาน'), findsOneWidget);
  });

  testWidgets('ไม่ส่ง onCopyToken ก็ไม่ขึ้นปุ่มคัดลอก', (tester) async {
    await _pumpView(tester, nowUtc: DateTime.utc(2026, 8, 2, 9, 0));
    expect(find.text('คัดลอกรหัส'), findsNothing);
  });
}
