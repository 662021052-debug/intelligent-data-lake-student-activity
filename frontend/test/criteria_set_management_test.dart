import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/models/learning_unit.dart';
import 'package:activity_tracking_frontend/screens/criteria_set_forms.dart';
import 'package:activity_tracking_frontend/screens/hour_categories_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/cohort_range.dart';
import 'package:activity_tracking_frontend/widgets/app_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

/// ค่าที่อยู่ในช่องกรอกลำดับที่ [index] — ใช้แทน find.text เมื่อค่าซ้ำกับ hint ของช่อง
String _fieldText(WidgetTester tester, int index) =>
    tester.widget<TextFormField>(find.byType(TextFormField).at(index)).controller!.text;

CriteriaSet _set({
  int id = 1,
  String code = '2570-regular',
  String name = 'เกณฑ์ 2570 หลักสูตรปกติ',
  int effectiveFromCohort = 2570,
  bool isSystem = false,
  String? hoursWarning,
  String programType = 'regular',
}) =>
    CriteriaSet(
      id: id,
      code: code,
      name: name,
      academicYear: 2570,
      programType: programType,
      totalRequiredHours: 60,
      effectiveFromCohort: effectiveFromCohort,
      isSystem: isSystem,
      hoursWarning: hoursWarning,
    );

void main() {
  group('ป้ายบอกรุ่นที่ใช้ชุดเกณฑ์', () {
    test('แปลงปีรุ่นเป็น "ใช้กับนิสิตรหัส XX ขึ้นไป"', () {
      expect(_set(effectiveFromCohort: 2570).audienceLabel,
          'ใช้กับนิสิตรหัส 70 ขึ้นไป (เข้าศึกษา 2570)');
      expect(_set(effectiveFromCohort: 2567).audienceLabel,
          'ใช้กับนิสิตรหัส 67 ขึ้นไป (เข้าศึกษา 2567)');
    });

    test('รุ่นที่ลงท้ายด้วยเลขหลักเดียวต้องเติมศูนย์ ไม่ใช่ "รหัส 5 ขึ้นไป"', () {
      expect(_set(effectiveFromCohort: 2605).audienceLabel, contains('รหัส 05 ขึ้นไป'));
    });

    test('ชุดขั้นล่างสุด (รุ่น 0) เขียนเป็นช่วง ไม่ใช่ "รหัส 00 ขึ้นไป"', () {
      final label = _set(effectiveFromCohort: 0).audienceLabel;
      expect(label, isNot(contains('00')));
      expect(label, contains('รุ่นก่อนหน้า'));
    });

    test('ป้ายกลุ่มหลักสูตรเป็นภาษาไทย', () {
      expect(_set().programTypeLabel, 'หลักสูตรปกติ');
      expect(_set(programType: 'continuing').programTypeLabel, 'หลักสูตรต่อเนื่อง');
    });
  });

  group('อ่านฟิลด์ใหม่จาก GET /criteria-sets', () {
    test('รับ effective_from_cohort / is_system / hours_warning มาครบ', () {
      final parsed = CriteriaSet.fromJson({
        'id': 2,
        'code': '2567-regular',
        'name': 'เกณฑ์ 2567',
        'academic_year': 2567,
        'program_type': 'regular',
        'effective_from_cohort': 2567,
        'total_required_hours': 60.0,
        'counting_rule': 'min_per_requirement',
        'is_system': true,
        'grouped_by': 'talent',
        'hours_warning': 'ผลรวมชั่วโมงของรายการเกณฑ์ (30 ชม.) ไม่เท่ากับชั่วโมงรวมของชุด (60 ชม.)',
        'groups': [],
      });

      expect(parsed.effectiveFromCohort, 2567);
      expect(parsed.isSystem, isTrue);
      expect(parsed.hoursWarning, contains('30 ชม.'));
      expect(parsed.countingRule, 'min_per_requirement');
    });

    test('payload เก่าที่ไม่มีฟิลด์ใหม่ต้องไม่พัง', () {
      final parsed = CriteriaSet.fromJson({
        'id': 1,
        'code': 'legacy-2566',
        'name': 'เกณฑ์เดิม',
        'groups': [],
      });

      expect(parsed.effectiveFromCohort, 0);
      expect(parsed.isSystem, isFalse);
      expect(parsed.hoursWarning, isNull);
    });
  });

  group('หัวข้อชุดเกณฑ์', () {
    testWidgets('ชุดของระบบมีป้าย "เกณฑ์ทางการ" และไม่มีปุ่มแก้/ลบ', (tester) async {
      await tester.pumpWidget(_wrap(const CriteriaSetHeader(
        badge: 'ชุดที่ 1',
        title: 'เกณฑ์ 2567 หลักสูตรปกติ',
        audience: 'ใช้กับนิสิตรหัส 67 ขึ้นไป (เข้าศึกษา 2567)',
        totalHours: 60,
        palette: StatusPalette.info,
        readOnly: true,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('เกณฑ์ทางการ'), findsOneWidget);
      expect(find.byTooltip('แก้ไขชุดเกณฑ์'), findsNothing);
      expect(find.byTooltip('ลบชุดเกณฑ์'), findsNothing);
    });

    testWidgets('ชุดของผู้ดูแลมีปุ่มแก้/ลบ และไม่มีป้ายอ่านอย่างเดียว', (tester) async {
      var edited = false;
      var deleted = false;
      await tester.pumpWidget(_wrap(CriteriaSetHeader(
        badge: 'ชุดของผู้ดูแล',
        title: 'เกณฑ์ 2570 หลักสูตรปกติ',
        audience: 'ใช้กับนิสิตรหัส 70 ขึ้นไป (เข้าศึกษา 2570)',
        totalHours: 60,
        palette: StatusPalette.approved,
        onEdit: () => edited = true,
        onDelete: () => deleted = true,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('เกณฑ์ทางการ'), findsNothing);
      await tester.tap(find.byTooltip('แก้ไขชุดเกณฑ์'));
      await tester.tap(find.byTooltip('ลบชุดเกณฑ์'));
      expect(edited, isTrue);
      expect(deleted, isTrue);
    });

    testWidgets('บอกรุ่นที่ใช้และชั่วโมงรวม', (tester) async {
      await tester.pumpWidget(_wrap(CriteriaSetHeader(
        badge: 'ชุดของผู้ดูแล',
        title: 'เกณฑ์ 2570',
        audience: _set().audienceLabel,
        totalHours: 60,
        palette: StatusPalette.approved,
      )));
      await tester.pumpAndSettle();

      expect(find.text('ใช้กับนิสิตรหัส 70 ขึ้นไป (เข้าศึกษา 2570)'), findsOneWidget);
      expect(find.text('60 ชม.'), findsOneWidget, reason: 'การ์ด metric ชั่วโมงรวม');
    });

    testWidgets('โชว์ hours_warning เมื่อชั่วโมงยังไม่ครบ', (tester) async {
      const warning = 'ผลรวมชั่วโมงของรายการเกณฑ์ (30 ชม.) ไม่เท่ากับชั่วโมงรวมของชุด (60 ชม.)';
      await tester.pumpWidget(_wrap(const CriteriaSetHeader(
        badge: 'ชุดของผู้ดูแล',
        title: 'เกณฑ์ 2570',
        audience: 'ใช้กับนิสิตรหัส 70 ขึ้นไป',
        totalHours: 60,
        palette: StatusPalette.approved,
        warning: warning,
      )));
      await tester.pumpAndSettle();

      expect(find.text(warning), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('ชั่วโมงครบแล้วต้องไม่มีคำเตือนค้างอยู่', (tester) async {
      await tester.pumpWidget(_wrap(const CriteriaSetHeader(
        badge: 'ชุดของผู้ดูแล',
        title: 'เกณฑ์ 2570',
        audience: 'ใช้กับนิสิตรหัส 70 ขึ้นไป',
        totalHours: 60,
        palette: StatusPalette.approved,
      )));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });
  });

  group('ฟอร์มชุดเกณฑ์', () {
    testWidgets('สร้างใหม่: มีช่องครบตามที่ backend ต้องการ', (tester) async {
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog()));
      await tester.pumpAndSettle();

      expect(find.text('เพิ่มชุดเกณฑ์ใหม่'), findsOneWidget);
      for (final label in [
        'รหัสชุด *',
        'ชื่อชุดเกณฑ์ *',
        'ปีหลักสูตร (พ.ศ.) *',
        'ปีรุ่นที่เริ่มใช้ (พ.ศ.) *',
        'กลุ่มหลักสูตร *',
        'ชั่วโมงรวมของชุด *',
        'วิธีนับความครบ *',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'ไม่พบช่อง "$label"');
      }
    });

    testWidgets('บอกผลของปีรุ่นให้ชัด ไม่ให้กรอกมั่ว', (tester) async {
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('นิสิตที่เข้าศึกษาตั้งแต่ปีนี้เป็นต้นไปจะใช้ชุดนี้'),
        findsOneWidget,
      );
    });

    testWidgets('โหมดแก้ไขเติมค่าเดิมมาให้ครบ', (tester) async {
      await tester.pumpWidget(_wrap(CriteriaSetFormDialog(existing: _set())));
      await tester.pumpAndSettle();

      expect(find.text('แก้ไขชุดเกณฑ์'), findsOneWidget);
      expect(find.text('2570-regular'), findsOneWidget);
      expect(find.text('เกณฑ์ 2570 หลักสูตรปกติ'), findsOneWidget);
      expect(_fieldText(tester, 2), '2570', reason: 'ปีหลักสูตร');
      expect(_fieldText(tester, 3), '2570', reason: 'ปีรุ่นที่เริ่มใช้');
      expect(_fieldText(tester, 4), '60', reason: 'ชั่วโมงรวม');
    });

    testWidgets('กรอกปีรุ่นผิดแล้วกดบันทึก ต้องเตือน ไม่ยิง API', (tester) async {
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(3), '9999');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('ปีรุ่นต้องอยู่ระหว่าง 0–2700'), findsOneWidget);
    });

    test('ตัวตรวจปีรุ่นตรงกับช่วงที่ backend รับ (0–2700)', () {
      expect(cohortValidator('2570'), isNull);
      expect(cohortValidator('0'), isNull);
      expect(cohortValidator(''), isNotNull);
      expect(cohortValidator('-1'), isNotNull);
      expect(cohortValidator('2701'), isNotNull);
      expect(cohortValidator('ปี 2570'), isNotNull);
    });

    test('ชั่วโมงต้องมากกว่า 0 เหมือนกฎ gt=0 ของ backend', () {
      expect(positiveNumberValidator('60'), isNull);
      expect(positiveNumberValidator('7.5'), isNull);
      expect(positiveNumberValidator('0'), 'ต้องมากกว่า 0');
      expect(positiveNumberValidator('-4'), 'ต้องมากกว่า 0');
      expect(positiveNumberValidator('abc'), 'กรอกตัวเลข');
    });
  });

  group('ฟอร์มรายการเกณฑ์', () {
    const units = [
      LearningUnit(id: 1, code: '1', name: 'พัฒนาทักษะชีวิต'),
      LearningUnit(id: 5, code: '5', name: 'ใฝ่เรียนรู้ตลอดชีวิต'),
    ];

    testWidgets('เลือกหน่วยการเรียนรู้ · ชั่วโมง · บังคับ/เลือก ได้ครบ', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementFormDialog(
        criteriaSetId: 1,
        learningUnits: units,
      )));
      await tester.pumpAndSettle();

      expect(find.text('ชื่อรายการ *'), findsOneWidget);
      expect(find.text('หน่วยการเรียนรู้ *'), findsOneWidget);
      expect(find.text('ชั่วโมงที่ต้องได้ *'), findsOneWidget);
      expect(find.text('เป็นรายการบังคับ'), findsOneWidget);
      // หน่วยแรกถูกเลือกไว้ให้ ไม่ปล่อยว่างจนกดบันทึกแล้วค่อยฟ้อง
      expect(find.text('1. พัฒนาทักษะชีวิต'), findsWidgets);
    });

    testWidgets('ไม่มี Talent/กลุ่มในชุด ก็ไม่ต้องโชว์ช่องให้รก', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementFormDialog(
        criteriaSetId: 1,
        learningUnits: units,
      )));
      await tester.pumpAndSettle();

      expect(find.text('อยู่ใน Talent (ไม่บังคับ)'), findsNothing);
      expect(find.text('กลุ่มแชร์เป้าชั่วโมง (ไม่บังคับ)'), findsNothing);
    });

    testWidgets('มี Talent ในชุดแล้วต้องเลือกได้', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementFormDialog(
        criteriaSetId: 1,
        learningUnits: units,
        talents: [
          {'id': 3, 'name': 'TSU Glocal Talent'},
        ],
      )));
      await tester.pumpAndSettle();

      expect(find.text('อยู่ใน Talent (ไม่บังคับ)'), findsOneWidget);
    });

    testWidgets('โหมดแก้ไขเติมค่าเดิม', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementFormDialog(
        criteriaSetId: 1,
        learningUnits: units,
        existing: {
          'id': 9,
          'name': 'กิจกรรมปฐมนิเทศนิสิต',
          'required_hours': 4,
          'is_mandatory': true,
          'learning_unit_id': 5,
        },
      )));
      await tester.pumpAndSettle();

      expect(find.text('แก้ไขรายการเกณฑ์'), findsOneWidget);
      expect(find.text('กิจกรรมปฐมนิเทศนิสิต'), findsOneWidget);
      expect(_fieldText(tester, 1), '4', reason: 'ชั่วโมงที่ต้องได้');
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    });
  });

  group('ผูกรายการเกณฑ์เข้ากลุ่มแชร์เป้า', () {
    const units = [LearningUnit(id: 5, code: '5', name: 'ใฝ่เรียนรู้ตลอดชีวิต')];

    test('อ่าน group_id ของรายการ และ requirement_groups ของชุด', () {
      final parsed = CriteriaSet.fromJson({
        'id': 7,
        'code': '2570-regular',
        'name': 'เกณฑ์ 2570',
        'groups': [
          {
            'key': 'talent:3',
            'name': 'TSU Social Talent',
            'requirements': [
              {'id': 11, 'name': 'ด้านนวัตกรรมสังคม', 'group_id': 2, 'group_name': 'กลุ่ม Social'},
              {'id': 12, 'name': 'ด้านผู้ประกอบการ', 'group_id': 2, 'group_name': 'กลุ่ม Social'},
            ],
          },
        ],
        'requirement_groups': [
          {'id': 2, 'code': 'social-16', 'name': 'กลุ่ม Social', 'required_hours': 16},
          {'id': 4, 'code': 'empty', 'name': 'กลุ่มใหม่', 'required_hours': 8},
        ],
      });

      expect(parsed.requirements.map((r) => r.groupId), [2, 2]);
      expect(parsed.requirementGroups.map((g) => g.id), [2, 4]);
      expect(parsed.requirementGroups.first.requiredHours, 16);
    });

    test('กลุ่มที่เพิ่งสร้าง (ยังไม่มีสมาชิก) ต้องเลือกได้ในฟอร์ม', () {
      const set = CriteriaSet(
        id: 7,
        code: '2570-regular',
        name: 'เกณฑ์ 2570',
        requirementGroups: [
          RequirementGroupOption(id: 4, code: 'social-16', name: 'กลุ่ม Social', requiredHours: 16),
        ],
      );

      final options = requirementGroupOptions(set);
      expect(options, hasLength(1));
      expect(options.single['id'], 4);
      expect(options.single['name'], 'กลุ่ม Social (รวม ≥ 16 ชม.)');
    });

    test('ถอด id ของ Talent จากกุญแจหัวข้อ', () {
      expect(talentIdOfGroup(const CriteriaGroup(key: 'talent:3', name: 'x')), 3);
      expect(talentIdOfGroup(const CriteriaGroup(key: 'talent:none', name: 'x')), isNull);
      expect(talentIdOfGroup(const CriteriaGroup(key: 'unit:5', name: 'x')), isNull);
    });

    testWidgets('มีกลุ่มในชุดแล้วต้องมีช่องเลือกกลุ่ม', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementFormDialog(
        criteriaSetId: 7,
        learningUnits: units,
        groups: [
          {'id': 4, 'name': 'กลุ่ม Social (รวม ≥ 16 ชม.)'},
        ],
      )));
      await tester.pumpAndSettle();

      expect(find.text('กลุ่มแชร์เป้าชั่วโมง (ไม่บังคับ)'), findsOneWidget);
      await tester.tap(find.text('ไม่อยู่ในกลุ่มใด'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('กลุ่ม Social (รวม ≥ 16 ชม.)').last);
      await tester.pumpAndSettle();

      // เมนูปิดแล้ว ช่องแสดงกลุ่มที่เลือกแทน "ไม่อยู่ในกลุ่มใด"
      expect(find.text('กลุ่ม Social (รวม ≥ 16 ชม.)'), findsOneWidget);
      expect(find.text('ไม่อยู่ในกลุ่มใด'), findsNothing);
    });

    testWidgets('โหมดแก้ไขเลือกกลุ่มเดิมไว้ให้ ไม่หลุดกลุ่มตอนกดบันทึก', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementFormDialog(
        criteriaSetId: 7,
        learningUnits: units,
        groups: [
          {'id': 4, 'name': 'กลุ่ม Social (รวม ≥ 16 ชม.)'},
        ],
        existing: {
          'id': 11,
          'name': 'ด้านนวัตกรรมสังคม',
          'required_hours': 16,
          'learning_unit_id': 5,
          'group_id': 4,
        },
      )));
      await tester.pumpAndSettle();

      expect(find.text('กลุ่ม Social (รวม ≥ 16 ชม.)'), findsOneWidget);
    });

    testWidgets('กลุ่มเดิมที่ไม่มีแล้วตกเป็น "ไม่อยู่ในกลุ่มใด" ไม่ทำฟอร์มพัง', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementFormDialog(
        criteriaSetId: 7,
        learningUnits: units,
        groups: [
          {'id': 4, 'name': 'กลุ่ม Social (รวม ≥ 16 ชม.)'},
        ],
        existing: {
          'id': 11,
          'name': 'ด้านนวัตกรรมสังคม',
          'required_hours': 16,
          'learning_unit_id': 5,
          'group_id': 99,
        },
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ไม่อยู่ในกลุ่มใด'), findsOneWidget);
    });
  });

  group('ฟอร์ม Talent และกลุ่มแชร์เป้า', () {
    testWidgets('ฟอร์ม Talent มีรหัส/ชื่อ/PLO/ลำดับ', (tester) async {
      await tester.pumpWidget(_wrap(const TalentFormDialog(criteriaSetId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('เพิ่ม Talent'), findsOneWidget);
      expect(find.text('รหัส *'), findsOneWidget);
      expect(find.text('ชื่อ *'), findsOneWidget);
      expect(find.text('PLO (ไม่บังคับ)'), findsOneWidget);
      expect(find.text('ลำดับการแสดง *'), findsOneWidget);
    });

    testWidgets('ฟอร์มกลุ่มอธิบายว่าตรวจที่ยอดรวมของกลุ่ม', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementGroupFormDialog(criteriaSetId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('เพิ่มกลุ่มแชร์เป้าชั่วโมง'), findsOneWidget);
      expect(find.text('ชั่วโมงรวมของกลุ่ม *'), findsOneWidget);
      expect(
        find.textContaining('ตรวจความครบที่ "ยอดรวมของกลุ่ม" ไม่ใช่ทีละรายการ'),
        findsOneWidget,
      );
    });

    testWidgets('โหมดแก้ไขกลุ่มเติมค่าเดิม', (tester) async {
      await tester.pumpWidget(_wrap(const RequirementGroupFormDialog(
        criteriaSetId: 1,
        existing: {
          'id': 2,
          'code': 'social-16',
          'name': 'กลุ่ม Social',
          'required_hours': 16,
          'rule_note': 'เลือกด้านเดียวหรือรวมสองด้าน',
        },
      )));
      await tester.pumpAndSettle();

      expect(find.text('แก้ไขกลุ่มแชร์เป้าชั่วโมง'), findsOneWidget);
      expect(find.text('social-16'), findsOneWidget);
      expect(_fieldText(tester, 2), '16', reason: 'ชั่วโมงรวมของกลุ่ม');
      expect(find.text('เลือกด้านเดียวหรือรวมสองด้าน'), findsOneWidget);
    });
  });

  group('ปุ่มเพิ่มอยู่ในกรอบของชุดที่มันแก้ + บอกว่าทำอะไรได้', () {
    Finder inHeader(Finder matching) =>
        find.descendant(of: find.byType(CriteriaSetHeader), matching: matching);

    testWidgets('เกณฑ์เดิม: ปุ่ม "เพิ่มหมวดใหญ่" อยู่ในกรอบนี้ และบอกว่าเป็นของรุ่น 66 ลงไป',
        (tester) async {
      var added = 0;
      await tester.pumpWidget(_wrap(legacyCriteriaSectionHeader(
        range: const CohortRange(from: 0, until: 2566),
        academicYear: 2569,
        totalHours: 60,
        categoryCount: 5,
        subcategoryCount: 20,
        onAddCategory: () => added++,
      )));
      await tester.pumpAndSettle();

      final button = inHeader(find.widgetWithText(OutlinedButton, kAddLegacyCategoryLabel));
      expect(button, findsOneWidget);
      expect(kAddLegacyCategoryLabel, contains('≤66'));
      expect(inHeader(find.text('ใช้กับรหัส ≤66')), findsOneWidget);
      expect(find.text('เข้าศึกษาปี 2566 ลงไป (ปัจจุบัน = ปี 4 ขึ้นไป)'), findsOneWidget);
      expect(inHeader(find.textContaining('เพิ่มได้: หมวดใหญ่')), findsOneWidget);
      expect(inHeader(find.textContaining('หมวดย่อย')), findsWidgets);
      expect(inHeader(find.textContaining('มีผลเฉพาะนิสิตรหัส ≤66')), findsOneWidget);

      await tester.tap(button);
      expect(added, 1);
    });

    testWidgets('ชุดทางการ 2567: ไม่มีปุ่มเลย บอกว่าดูอย่างเดียว และชี้ไปปุ่มสร้างชุดใหม่',
        (tester) async {
      await tester.pumpWidget(_wrap(systemCriteriaSectionHeader(
        _set(code: '2567-regular', effectiveFromCohort: 2567, isSystem: true),
      )));
      await tester.pumpAndSettle();

      expect(inHeader(find.byType(OutlinedButton)), findsNothing);
      expect(inHeader(find.byType(FilledButton)), findsNothing);
      expect(inHeader(find.byType(AppIconButton)), findsNothing);
      expect(inHeader(find.textContaining('ดูได้อย่างเดียว')), findsOneWidget);
      expect(inHeader(find.textContaining('"$kAddCriteriaSetLabel"')), findsOneWidget);
      expect(inHeader(find.byIcon(Icons.lock_outline)), findsWidgets);
    });

    testWidgets('ชุดของผู้ดูแล: ปุ่มเพิ่ม Talent/กลุ่ม/รายการ + แก้/ลบชุด อยู่ในกรอบของชุด',
        (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(_wrap(SingleChildScrollView(
        child: customCriteriaSectionHeader(
          _set(),
          onEdit: () => pressed.add('edit'),
          onDelete: () => pressed.add('delete'),
          onAddTalent: () => pressed.add('talent'),
          onAddGroup: () => pressed.add('group'),
          onAddRequirement: () => pressed.add('requirement'),
        ),
      )));
      await tester.pumpAndSettle();

      for (final label in ['เพิ่ม Talent', 'เพิ่มกลุ่มแชร์เป้า', 'เพิ่มรายการเกณฑ์']) {
        await tester.tap(inHeader(find.widgetWithText(OutlinedButton, label)));
      }
      await tester.tap(inHeader(find.byTooltip('แก้ไขชุดเกณฑ์')));
      await tester.tap(inHeader(find.byTooltip('ลบชุดเกณฑ์')));
      expect(pressed, ['talent', 'group', 'requirement', 'edit', 'delete']);

      // ปุ่มของโครงเก่าต้องไม่หลุดมาอยู่ในชุดใหม่
      expect(find.textContaining('เพิ่มหมวดใหญ่'), findsNothing);
      expect(inHeader(find.textContaining('แก้ได้ทั้งชุด')), findsOneWidget);
      expect(inHeader(find.textContaining('มีผลกับนิสิตรหัส 70 ขึ้นไป')), findsOneWidget);
    });
  });

  group('ปุ่มบนหัวข้อชุด', () {
    testWidgets('ปุ่มแก้/ลบของชุดเป็น AppIconButton ที่มี tooltip เสมอ', (tester) async {
      await tester.pumpWidget(_wrap(CriteriaSetHeader(
        badge: 'ชุดของผู้ดูแล',
        title: 'เกณฑ์ 2570',
        audience: 'ใช้กับนิสิตรหัส 70 ขึ้นไป',
        totalHours: 60,
        palette: StatusPalette.approved,
        onEdit: () {},
        onDelete: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.byType(AppIconButton), findsNWidgets(2));
    });
  });
}
