import 'package:activity_tracking_frontend/models/participation.dart';
import 'package:flutter_test/flutter_test.dart';

/// snapshot เกณฑ์ที่ตรึงไว้ตอนอนุมัติ — หน้า "การเข้าร่วมกิจกรรม" เอามาแสดง
/// ว่าชั่วโมงของรายการนั้นถูกนับเข้าอะไร
void main() {
  group('อ่าน snapshot เกณฑ์จาก API', () {
    test('รับทั้ง requirement_name และ learning_unit_name ที่ backend เพิ่มมาให้', () {
      final p = Participation.fromJson(const {
        'id': 5,
        'student_id': 1,
        'activity_id': 2,
        'hours_earned': 4,
        'evidence_status': 'approved',
        'requirement_name': 'กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์)',
        'learning_unit_name': 'TSU รับใช้สังคม',
      });

      expect(p.requirementName, 'กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์)');
      expect(p.learningUnitName, 'TSU รับใช้สังคม');
      expect(p.hoursEarned, 4);
    });

    test('แถวเก่าที่ไม่มีสองฟิลด์นี้ยังอ่านได้ ไม่ล้ม', () {
      final p = Participation.fromJson(const {
        'id': 6,
        'student_id': 1,
        'activity_id': 2,
        'evidence_status': 'pending',
      });

      expect(p.requirementName, isNull);
      expect(p.learningUnitName, isNull);
    });
  });

  group('ป้าย "นับเข้าหมวด"', () {
    Participation of({String? requirement, String? unit}) => Participation(
          studentId: 1,
          activityId: 2,
          requirementName: requirement,
          learningUnitName: unit,
        );

    test('มีครบทั้งคู่ = "รายการเกณฑ์ (หน่วยการเรียนรู้)"', () {
      expect(
        of(requirement: 'กิจกรรมปฐมนิเทศนิสิต', unit: 'ใฝ่เรียนรู้ตลอดชีวิต').criteriaLabel,
        'กิจกรรมปฐมนิเทศนิสิต (ใฝ่เรียนรู้ตลอดชีวิต)',
      );
    });

    test('มีอย่างเดียวก็แสดงตัวที่มี ไม่โชว์วงเล็บว่าง', () {
      expect(of(requirement: 'กิจกรรมปฐมนิเทศนิสิต').criteriaLabel, 'กิจกรรมปฐมนิเทศนิสิต');
      expect(of(unit: 'TSU รับใช้สังคม').criteriaLabel, 'TSU รับใช้สังคม');
    });

    test('ยังไม่อนุมัติ = ยังไม่มี snapshot จึงว่าง (หน้าจอแสดง "–")', () {
      expect(of().criteriaLabel, isEmpty);
    });
  });
}
