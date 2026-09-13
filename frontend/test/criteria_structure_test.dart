import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/screens/hour_categories_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// รูปคำตอบจริงของ `GET /criteria-sets` (ย่อมาจากข้อมูลบน Postgres)
const _payload2567 = {
  'id': 1,
  'code': '2567-regular',
  'name': 'เกณฑ์ 2567 หลักสูตรปกติ (60 ชม.)',
  'academic_year': 2567,
  'total_required_hours': 60.0,
  'counting_rule': 'min_per_requirement',
  'grouped_by': 'talent',
  'groups': [
    {
      'key': 'talent:1',
      'name': 'TSU Glocal Talent',
      'subtitle': 'PLO 1',
      'requirements': [
        {
          'id': 1,
          'name': 'กิจกรรมปฐมนิเทศนิสิต',
          'required_hours': 4.0,
          'is_mandatory': true,
          'learning_unit_name': 'ใฝ่เรียนรู้ตลอดชีวิต',
          'group_name': null,
        },
      ],
    },
    {
      'key': 'talent:2',
      'name': 'TSU Communication Talent',
      'subtitle': 'PLO 2',
      'requirements': [
        {
          'id': 2,
          'name': 'ทักษะการใช้ภาษาเพื่อการสื่อสารในชีวิตประจำวัน',
          'required_hours': 10.0,
          'is_mandatory': false,
          'learning_unit_name': 'ศิลปวัฒนธรรมอาเซียน',
          'group_name': null,
        },
      ],
    },
    {
      'key': 'talent:3',
      'name': 'TSU Social Innovation/Entrepreneurship Talent',
      'subtitle': 'PLO 3',
      'requirements': [
        {
          'id': 3,
          'name': 'ด้านการสร้างนวัตกรรมสังคม',
          'required_hours': 16.0,
          'is_mandatory': false,
          'learning_unit_name': 'ใฝ่เรียนรู้ตลอดชีวิต',
          'group_name': 'ด้านนวัตกรรมสังคม/ผู้ประกอบการ (เลือกด้านเดียวหรือรวมสองด้าน)',
        },
      ],
    },
  ],
};

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

void main() {
  group('ชุดเกณฑ์ 2567 จาก /criteria-sets', () {
    final set = CriteriaSet.fromJson(Map<String, dynamic>.from(_payload2567));

    test('อ่าน Talent/PLO ครบ 3 หมวดหลัก', () {
      expect(set.groupedBy, 'talent');
      expect(set.groups.map((g) => g.subtitle).toList(), ['PLO 1', 'PLO 2', 'PLO 3']);
      expect(set.groups.first.name, 'TSU Glocal Talent');
    });

    test('ชั่วโมงรวมของชุดมาจาก total_required_hours ไม่ใช่ผลบวกของรายการ', () {
      // ผลบวกรายการคือ 4+10+16 = 30 แต่เกณฑ์จริงคือ 60 ชม.
      // (รายการ "เลือก" กับกฎกลุ่มทำให้สองตัวเลขไม่เท่ากันโดยธรรมชาติ)
      expect(set.totalRequiredHours, 60);
    });

    test('รายการเกณฑ์บอกครบทั้งชั่วโมง บังคับ/เลือก หน่วย และกฎกลุ่ม', () {
      final mandatory = set.groups[0].requirements.single;
      expect(mandatory.requiredHours, 4);
      expect(mandatory.isMandatory, isTrue);
      expect(mandatory.learningUnitName, 'ใฝ่เรียนรู้ตลอดชีวิต');
      expect(mandatory.groupName, isNull);

      final grouped = set.groups[2].requirements.single;
      expect(grouped.isMandatory, isFalse);
      expect(grouped.requiredHours, 16, reason: 'กฎ Social รวม ≥ 16');
      expect(grouped.groupName, contains('นวัตกรรมสังคม'));
    });
  });

  group('ค้นหาในโครงสร้าง 2567', () {
    final groups =
        CriteriaSet.fromJson(Map<String, dynamic>.from(_payload2567)).groups;

    test('คำค้นว่าง = เห็นทุกหมวด', () {
      expect(filterCriteriaGroups(groups, '').length, 3);
    });

    test('ชื่อหมวดตรง', () {
      final found = filterCriteriaGroups(groups, 'Communication');
      expect(found.map((g) => g.subtitle).toList(), ['PLO 2']);
    });

    test('ชื่อรายการข้างในตรง ก็ต้องเก็บหมวดแม่ไว้', () {
      final found = filterCriteriaGroups(groups, 'ปฐมนิเทศ');
      expect(found.map((g) => g.subtitle).toList(), ['PLO 1']);
    });

    test('ไม่ตรงเลยได้ผลว่าง ไม่ใช่คืนทุกหมวด', () {
      expect(filterCriteriaGroups(groups, 'ไม่มีคำนี้'), isEmpty);
    });
  });

  group('หัวข้อกำกับชุดเกณฑ์', () {
    testWidgets('บอกชื่อชุด รุ่นนิสิตที่ใช้ และชั่วโมงรวม', (tester) async {
      await tester.pumpWidget(_wrap(const CriteriaSetHeader(
        badge: 'ชุดที่ 1',
        title: 'โครงสร้าง 2567',
        audience: 'สำหรับนิสิตรหัส 67 ขึ้นไป (ปัจจุบัน ปี 1-3)',
        totalHours: 60,
        palette: StatusPalette.info,
        note: 'นิยามชุดนี้กำหนดไว้ในระบบ แก้ผ่านหน้านี้ไม่ได้',
      )));
      await tester.pumpAndSettle();

      expect(find.text('ชุดที่ 1'), findsOneWidget);
      expect(find.text('โครงสร้าง 2567'), findsOneWidget);
      expect(find.text('สำหรับนิสิตรหัส 67 ขึ้นไป (ปัจจุบัน ปี 1-3)'), findsOneWidget);
      expect(find.text('· รวม 60 ชม.'), findsOneWidget);
      expect(find.text('นิยามชุดนี้กำหนดไว้ในระบบ แก้ผ่านหน้านี้ไม่ได้'), findsOneWidget);
    });

    testWidgets('สองชุดต้องใช้สีต่างกัน ไม่ให้อ่านต่อกันเป็นชุดเดียว', (tester) async {
      await tester.pumpWidget(_wrap(Column(
        children: const [
          CriteriaSetHeader(
            key: ValueKey('set1'),
            badge: 'ชุดที่ 1',
            title: 'โครงสร้าง 2567',
            audience: 'รหัส 67 ขึ้นไป',
            totalHours: 60,
            palette: StatusPalette.info,
          ),
          CriteriaSetHeader(
            key: ValueKey('set2'),
            badge: 'ชุดที่ 2',
            title: 'เกณฑ์เดิม',
            audience: 'รหัส 66 ลงไป',
            totalHours: 60,
            palette: StatusPalette.neutral,
          ),
        ],
      )));
      await tester.pumpAndSettle();

      Color background(String key) {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Container),
          ).first,
        );
        return ((container.decoration as BoxDecoration).color)!;
      }

      expect(background('set1'), isNot(background('set2')));
      expect(find.text('เกณฑ์เดิม'), findsOneWidget);
      expect(find.text('รหัส 66 ลงไป'), findsOneWidget);
    });
  });
}
