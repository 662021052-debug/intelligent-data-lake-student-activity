import 'package:activity_tracking_frontend/models/participation.dart';
import 'package:activity_tracking_frontend/screens/app_shell.dart';
import 'package:activity_tracking_frontend/screens/evidence_review_screen.dart';
import 'package:activity_tracking_frontend/widgets/app_nav.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('เมนู "ตรวจหลักฐาน" บน sidebar', () {
    test('admin และ staff เห็นเมนู · นิสิตไม่เห็น', () {
      expect(navItemsForRole('admin').map((i) => i.id), contains('evidence_review'));
      expect(navItemsForRole('staff').map((i) => i.id), contains('evidence_review'));
      expect(navItemsForRole('student').map((i) => i.id), isNot(contains('evidence_review')));
    });

    test('กดเมนูแล้วเปิดคิวตรวจหลักฐาน', () {
      expect(screenForNavItem(AppNavItem.evidenceReview), isA<EvidenceReviewScreen>());
    });
  });

  group('query ของคิวตรวจหลักฐาน', () {
    test('ขอเฉพาะรายการที่ส่งไฟล์แล้วเสมอ แม้ไม่เลือกตัวกรอง', () {
      final query = evidenceReviewQuery(skip: 0, limit: 20);
      expect(query, {'skip': '0', 'limit': '20', 'has_evidence': 'true'});
    });

    test('ใส่สถานะ / ผล OCR / คำค้น เมื่อเลือก', () {
      final query = evidenceReviewQuery(
        skip: 20,
        limit: 20,
        evidenceStatus: 'pending',
        ocrDecision: 'flagged',
        search: 'สมชาย',
      );
      expect(query['has_evidence'], 'true');
      expect(query['evidence_status'], 'pending');
      expect(query['ocr_decision'], 'flagged');
      expect(query['search'], 'สมชาย');
      expect(query['skip'], '20');
    });
  });

  test('Participation อ่านชื่อและรหัสนิสิตจาก API', () {
    final p = Participation.fromJson({
      'id': 1,
      'student_id': 7,
      'activity_id': 3,
      'student_name': 'นายสมชาย ใจดี',
      'student_code': '690000001',
    });
    expect(p.studentName, 'นายสมชาย ใจดี');
    expect(p.studentCode, '690000001');
    expect(Participation.fromJson({'student_id': 7, 'activity_id': 3}).studentName, isNull);
  });
}
