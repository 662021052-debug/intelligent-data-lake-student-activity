import 'package:activity_tracking_frontend/models/ocr_result.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payload([Map<String, dynamic> extra = const {}]) => {
      'id': 7,
      'raw_file_id': 50,
      'participation_id': 91442,
      'extracted_text': 'มหาวิทยาลัยทักษิณ',
      'ocr_confidence': 0.69,
      'match_score': 0.76,
      'decision': 'flagged',
      'is_duplicate': true,
      'processed_at': '2026-09-14T06:12:14.193533',
      ...extra,
    };

void main() {
  group('OcrResult: ใบต้นทาง + เหตุผลที่ซ้ำ (OCR เฟส 1.2)', () {
    test('ผล OCR ก่อนเฟส 1.2 ไม่มีสองคีย์นี้เลย → null ไม่ล้ม', () {
      final result = OcrResult.fromJson(_payload());
      expect(result.isDuplicate, isTrue);
      expect(result.duplicateOfParticipationId, isNull);
      expect(result.duplicateReason, isNull);
    });

    test('backend ส่ง null มาตรง ๆ (ไฟล์ไม่ซ้ำ) → null', () {
      final result = OcrResult.fromJson(_payload({
        'decision': 'needs_review',
        'is_duplicate': false,
        'duplicate_of_participation_id': null,
        'duplicate_reason': null,
      }));
      expect(result.duplicateOfParticipationId, isNull);
      expect(result.duplicateReason, isNull);
    });

    for (final reason in ['cross_student', 'same_student_reuse', 'matches_rejected']) {
      test('อ่าน duplicate_of_participation_id + duplicate_reason=$reason', () {
        final result = OcrResult.fromJson(_payload({
          'duplicate_of_participation_id': 62162,
          'duplicate_reason': reason,
        }));
        expect(result.duplicateOfParticipationId, 62162);
        expect(result.duplicateReason, reason);
      });
    }
  });
}
