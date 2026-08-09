import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// กติกา "ห้ามตั้งกิจกรรมย้อนหลัง" ฝั่ง UI — ตรึงเวลาไว้ทุกเคสเพื่อไม่ให้ผลเทสต์
/// ขึ้นกับนาฬิกาของเครื่องที่รัน (เคสสำคัญคือรอยต่อเที่ยงคืน)
void main() {
  final now = DateTime(2026, 8, 5, 14, 30);

  group('วันแรกที่เลือกได้', () {
    test('คือเที่ยงคืนของวันนี้ — ตัดเวลาออกเพื่อให้เลือกวันนี้ได้ทั้งวัน', () {
      expect(activityFirstSelectableDate(now), DateTime(2026, 8, 5));
    });
  });

  group('isBackdatedActivity', () {
    test('เมื่อวานถือว่าย้อนหลัง', () {
      expect(isBackdatedActivity(DateTime(2026, 8, 4, 23, 59), now), isTrue);
    });

    test('เช้าวันนี้ที่ผ่านมาแล้วยังไม่ถือว่าย้อนหลัง (เทียบระดับวันเหมือน backend)', () {
      expect(isBackdatedActivity(DateTime(2026, 8, 5, 9, 0), now), isFalse);
    });

    test('เที่ยงคืนตรงของวันนี้ยังเลือกได้', () {
      expect(isBackdatedActivity(DateTime(2026, 8, 5), now), isFalse);
    });

    test('พรุ่งนี้และอนาคตเลือกได้', () {
      expect(isBackdatedActivity(DateTime(2026, 8, 6, 8, 0), now), isFalse);
      expect(isBackdatedActivity(DateTime(2027, 1, 1), now), isFalse);
    });
  });

  group('การจัดที่อยู่ของข้อความ error', () {
    test('ข้อความกันย้อนหลังจาก backend ต้องไปโผล่ใต้ช่องวันที่', () {
      // ข้อความไทยจาก backend ถูกส่งผ่าน apiErrorMessage มาตรง ๆ (ไม่ถูกแปลทับ)
      expect(isActivityDateError(kBackdatedActivityMessage), isTrue);
      expect(isActivityDateError('ไม่สามารถตั้งวันเวลากิจกรรมเป็นอดีตได้'), isTrue);
    });

    test('error อื่นยังอยู่ในกล่อง error รวมท้ายฟอร์มเหมือนเดิม', () {
      expect(isActivityDateError('คุณไม่มีสิทธิ์ทำรายการนี้'), isFalse);
      expect(isActivityDateError('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบว่าเปิด backend อยู่หรือไม่'),
          isFalse);
    });
  });
}
