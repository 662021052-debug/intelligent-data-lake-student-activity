import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({bool? isHidden, int participants = 0}) => {
      'id': 5,
      'name': 'ค่ายอาสา',
      'activity_type': 'จิตอาสา',
      'subcategory_id': 7,
      'hours': 4,
      'is_required': false,
      'max_participants': 50,
      'start_at': '2026-12-01T09:00:00',
      'location': 'ห้อง SC101',
      'approval_status': 'approved',
      'participant_count': participants,
      // ไม่ส่ง key นี้เลยเมื่อเป็น null — จำลอง backend รุ่นเก่าที่ยังไม่มีฟิลด์
      'is_hidden': ?isHidden,
    };

Activity _activity({int participants = 0}) => Activity(
      id: 5,
      name: 'ค่ายอาสา',
      activityType: 'จิตอาสา',
      maxParticipants: 50,
      startAt: DateTime(2026, 12, 1, 9, 0),
      location: 'ห้อง SC101',
      participantCount: participants,
    );

void main() {
  group('อ่านสถานะ "ซ่อนอยู่" จาก backend', () {
    test('is_hidden = true ถูกอ่านเข้ามาจริง', () {
      expect(Activity.fromJson(_json(isHidden: true)).isHidden, isTrue);
    });

    test('is_hidden = false ปกติ', () {
      expect(Activity.fromJson(_json(isHidden: false)).isHidden, isFalse);
    });

    test('backend รุ่นเก่าที่ยังไม่ส่ง is_hidden มา ต้องไม่พังและถือว่าไม่ซ่อน', () {
      expect(Activity.fromJson(_json()).isHidden, isFalse);
    });
  });

  group('กด "ลบ" แล้วจะได้ลบจริงหรือแค่ซ่อน', () {
    test('ยังไม่มีใครเข้าร่วม → ลบจริงได้', () {
      expect(activityWillBeHiddenOnDelete(_activity()), isFalse);
    });

    test('มีผู้เข้าร่วมแล้วแม้แค่คนเดียว → ซ่อนแทน (ชั่วโมงที่ให้ไปแล้วต้องไม่หาย)', () {
      expect(activityWillBeHiddenOnDelete(_activity(participants: 1)), isTrue);
      expect(activityWillBeHiddenOnDelete(_activity(participants: 40)), isTrue);
    });
  });
}
