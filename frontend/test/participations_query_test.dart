import 'package:activity_tracking_frontend/screens/participations_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('participationListQuery — หน้าการเข้าร่วมกิจกรรม', () {
    test('นิสิต: ขอให้ใบที่ยังต้องส่งหลักฐาน (pending/rejected) ขึ้นก่อน', () {
      final q = participationListQuery(isStudent: true, skip: 0, limit: 10);
      expect(q['needs_evidence_first'], 'true');
      // ไม่ตั้งตัวกรอง "รอตรวจสอบ" เป็นค่าเริ่ม — ใบที่ถูกปฏิเสธต้องยังเห็นและอัปโหลดใหม่ได้
      expect(q.containsKey('evidence_status'), isFalse);
    });

    test('เจ้าหน้าที่/แอดมิน: ลำดับเดิมตาม id ไม่ส่งพารามิเตอร์เรียง', () {
      final q = participationListQuery(isStudent: false, skip: 0, limit: 10);
      expect(q.containsKey('needs_evidence_first'), isFalse);
    });

    test('ตัวกรอง/ค้นหา/แบ่งหน้าส่งครบ และเรียงก่อนยังคงอยู่เมื่อกรองสถานะ', () {
      final q = participationListQuery(
        isStudent: true,
        skip: 20,
        limit: 10,
        activityId: 7,
        status: 'rejected',
        search: 'ค่าย',
      );
      expect(q, {
        'skip': '20',
        'limit': '10',
        'needs_evidence_first': 'true',
        'activity_id': '7',
        'evidence_status': 'rejected',
        'search': 'ค่าย',
      });
    });

    test('ค่าว่างไม่ถูกส่ง', () {
      final q = participationListQuery(isStudent: false, skip: 0, limit: 10, search: '');
      expect(q, {'skip': '0', 'limit': '10'});
    });
  });
}
