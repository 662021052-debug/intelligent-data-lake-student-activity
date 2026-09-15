import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/models/learning_unit.dart';
import 'package:activity_tracking_frontend/screens/criteria_set_forms.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

const _socialNote = 'กฎพิเศษ: «ด้านการสร้างนวัตกรรมสังคม» กับ «ด้านการเป็นผู้ประกอบการ» ใช้เป้าหมาย 16 ชม. ร่วมกัน';

void main() {
  group('แก้รายการเกณฑ์แล้วค่าเดิมที่ไม่มีช่องต้องไม่หาย (PUT แทนที่ทั้งแถว)', () {
    test('ส่ง organizer / min_activities เดิมกลับไป · rule_note มาจากช่องในฟอร์ม', () {
      final body = requirementFormPayload(
        name: ' ด้านการสร้างนวัตกรรมสังคม ',
        learningUnitId: 5,
        talentId: 3,
        groupId: 1,
        isMandatory: false,
        hours: '16',
        ruleNote: '  $_socialNote ',
        existing: {'id': 23, 'organizer': 'กองกิจการนิสิต', 'min_activities': 2},
      );
      expect(body, {
        'name': 'ด้านการสร้างนวัตกรรมสังคม',
        'learning_unit_id': 5,
        'talent_id': 3,
        'group_id': 1,
        'is_mandatory': false,
        'required_hours': 16.0,
        'rule_note': _socialNote,
        'organizer': 'กองกิจการนิสิต',
        'min_activities': 2,
      });
    });

    test('สร้างใหม่ (ไม่มีค่าเดิม) และช่องกฎว่าง → ส่ง null ไม่ใช่สตริงว่าง', () {
      final body = requirementFormPayload(
        name: 'รายการใหม่',
        learningUnitId: 1,
        talentId: null,
        groupId: null,
        isMandatory: true,
        hours: '4',
        ruleNote: '   ',
      );
      expect(body['rule_note'], isNull);
      expect(body['organizer'], isNull);
      expect(body['min_activities'], isNull);
    });

    test('อ่าน rule_note / organizer / min_activities จาก GET /criteria-sets', () {
      final item = CriteriaRequirement.fromJson({
        'id': 23,
        'name': 'ด้านการสร้างนวัตกรรมสังคม',
        'required_hours': 16,
        'rule_note': _socialNote,
        'organizer': 'กองกิจการนิสิต',
        'min_activities': 2,
      });
      expect(item.ruleNote, _socialNote);
      expect(item.organizer, 'กองกิจการนิสิต');
      expect(item.minActivities, 2);
    });

    testWidgets('เปิดฟอร์มแก้ไข: ช่องคำอธิบายกฎมีค่าเดิมมาให้ ไม่ใช่ว่างเปล่า', (tester) async {
      await tester.pumpWidget(_wrap(RequirementFormDialog(
        criteriaSetId: 2,
        learningUnits: [LearningUnit.fromJson({'id': 5, 'code': '5', 'name': 'ใฝ่เรียนรู้ตลอดชีวิต'})],
        existing: const {
          'id': 23,
          'name': 'ด้านการสร้างนวัตกรรมสังคม',
          'required_hours': 16,
          'is_mandatory': false,
          'learning_unit_id': 5,
          'rule_note': _socialNote,
        },
      )));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, _socialNote), findsOneWidget);
    });
  });
}
