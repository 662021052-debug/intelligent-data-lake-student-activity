import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/screens/hour_categories_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/cohort_range.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

CriteriaRequirement _req(int id, String name, double hours,
        {bool mandatory = false, int? groupId, String? groupName, String? unit}) =>
    CriteriaRequirement(
      id: id,
      name: name,
      requiredHours: hours,
      isMandatory: mandatory,
      groupId: groupId,
      groupName: groupName,
      learningUnitName: unit,
    );

// โครงเดียวกับข้อมูลจริงบน Postgres (ชุด 2567)
const _social = RequirementGroupOption(
  id: 1,
  code: 'social-16',
  name: 'ด้านนวัตกรรมสังคม/ผู้ประกอบการ',
  requiredHours: 16,
);

final _glocal = CriteriaGroup(key: 'talent:1', name: 'TSU Glocal Talent', subtitle: 'PLO 1', requirements: [
  _req(1, 'กิจกรรมปฐมนิเทศนิสิต', 4, mandatory: true, unit: 'ใฝ่เรียนรู้ตลอดชีวิต'),
  _req(2, 'กิจกรรมเกี่ยวกับการใช้ชีวิตในมหาวิทยาลัย', 4, mandatory: true),
  _req(3, 'การคิด วิจารณญาณ และการแก้ปัญหา', 3, unit: 'พัฒนาทักษะชีวิต'),
  _req(4, 'การบริหารจัดการตนเอง', 3),
  _req(5, 'การทำงานร่วมกับผู้อื่น', 3),
  _req(6, 'ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล', 3),
  _req(7, 'กลุ่ม TSU Good', 10),
]);

final _plo3 = CriteriaGroup(key: 'talent:3', name: 'TSU Social Innovation', subtitle: 'PLO 3', requirements: [
  _req(8, 'แนวคิดการเป็นนักนวัตกรรมสังคม/ผู้ประกอบการ', 4, mandatory: true),
  _req(9, 'ด้านการสร้างนวัตกรรมสังคม', 16, groupId: 1, groupName: _social.name),
  _req(10, 'ด้านการเป็นผู้ประกอบการ', 16, groupId: 1, groupName: _social.name),
]);

void main() {
  group('ตัวเลขบนหัวข้อ Talent', () {
    test('ผลรวมชั่วโมงของหัวข้อ = รายการปกติ + เป้ากลุ่มแชร์นับครั้งเดียว', () {
      expect(criteriaGroupTargetHours(_glocal, const [_social]), 30);
      expect(criteriaGroupTargetHours(_plo3, const [_social]), 20, reason: '4 + 16 ไม่ใช่ 36');
    });

    test('payload ที่มีแค่ชื่อกลุ่ม (ไม่มี requirement_groups) ก็ยังนับครั้งเดียว', () {
      final byName = CriteriaGroup(key: 'x', name: 'x', requirements: [
        _req(1, 'a', 4),
        _req(2, 'b', 16, groupName: 'สังคม'),
        _req(3, 'c', 16, groupName: 'สังคม'),
      ]);
      expect(criteriaGroupTargetHours(byName, const []), 20);
      expect(sharedTargetRules(byName, const []).single, startsWith('สังคม: 2 รายการ'));
    });

    test('แถบกฎกลุ่ม ≥16 ขึ้นเฉพาะหัวข้อที่มีกลุ่มแชร์เป้า', () {
      expect(sharedTargetRules(_glocal, const [_social]), isEmpty);
      expect(
        sharedTargetRules(_plo3, const [_social]).single,
        'ด้านนวัตกรรมสังคม/ผู้ประกอบการ: 2 รายการเลือกรวมกันต้อง ≥ 16 ชม. (ตรวจผลรวมอัตโนมัติ)',
      );
    });

    test('บรรทัดย่อยของรายการ: หน่วยการเรียนรู้ + บอกว่าใช้เป้าร่วม', () {
      expect(requirementSubtitle(_glocal.requirements[0]), 'หน่วยการเรียนรู้: ใฝ่เรียนรู้ตลอดชีวิต');
      expect(requirementSubtitle(_plo3.requirements[1]), 'ใช้เป้าร่วมของกลุ่ม');
      expect(requirementSubtitle(_glocal.requirements[1]), isNull);
    });
  });

  group('metric 3 ใบใต้หัวชุด', () {
    test('ชุด Talent: ชั่วโมงรวม · จำนวนกลุ่ม · วิธีนับ', () {
      final set = CriteriaSet(
        id: 2,
        code: '2567-regular',
        name: 'เกณฑ์ 2567',
        totalRequiredHours: 60,
        groups: [_glocal, _plo3, _glocal],
      );
      expect(criteriaSetMetrics(set).map((m) => '${m.value}/${m.label}').toList(),
          ['60 ชม./ชั่วโมงรวม', '3 กลุ่ม/Talent / PLO', 'ต่อรายการ/วิธีนับความครบ']);
    });

    test('ชุดหน่วยการเรียนรู้ นับต่อหน่วย', () {
      final set = CriteriaSet(
        id: 1,
        code: 'legacy',
        name: 'เดิม',
        totalRequiredHours: 60,
        groupedBy: 'learning_unit',
        countingRule: 'total_per_unit',
        groups: [_glocal],
      );
      expect(criteriaSetMetrics(set).map((m) => m.value).toList(), ['60 ชม.', '1 หน่วย', 'ต่อหน่วย']);
    });
  });

  group('หัวการ์ดชุด', () {
    testWidgets('ชุดทางการ: ป้ายชุด → ชื่อ → ช่วงรหัส + ป้ายล็อก + metric', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final set = CriteriaSet(
        id: 2,
        code: '2567-regular',
        name: 'เกณฑ์ 2567 หลักสูตรปกติ',
        totalRequiredHours: 60,
        effectiveFromCohort: 2567,
        isSystem: true,
        groups: [_glocal, _plo3],
      );
      await tester.pumpWidget(_wrap(systemCriteriaSectionHeader(set, allSets: [set], academicYear: 2569)));

      expect(find.text('ชุดที่ 1'), findsOneWidget);
      expect(find.text('ใช้กับรหัส 67 ขึ้นไป'), findsOneWidget);
      expect(find.text('เกณฑ์ทางการ · อ่านอย่างเดียว'), findsOneWidget);
      for (final text in ['60 ชม.', 'ชั่วโมงรวม', '2 กลุ่ม', 'ต่อรายการ', 'วิธีนับความครบ']) {
        expect(find.descendant(of: find.byKey(const ValueKey('criteria-metrics')), matching: find.text(text)),
            findsOneWidget, reason: text);
      }
      // ลำดับซ้าย → ขวา: ป้ายชุด < ชื่อ < ช่วงรหัส < ป้ายล็อก (ชิดขวา)
      final xs = [
        tester.getTopLeft(find.text('ชุดที่ 1')).dx,
        tester.getTopLeft(find.text('เกณฑ์ 2567 หลักสูตรปกติ')).dx,
        tester.getTopLeft(find.byKey(const ValueKey('cohort-range-pill'))).dx,
        tester.getTopLeft(find.text('เกณฑ์ทางการ · อ่านอย่างเดียว')).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(tester.getTopRight(find.text('เกณฑ์ทางการ · อ่านอย่างเดียว')).dx, greaterThan(1150),
          reason: 'ป้ายล็อกชิดขวา');
    });

    testWidgets('เกณฑ์เดิม: metric เป็นหน่วย + วิธีนับต่อหน่วย', (tester) async {
      await tester.pumpWidget(_wrap(legacyCriteriaSectionHeader(
        range: const CohortRange(from: 0, until: 2566),
        title: 'เกณฑ์เดิม (โครงสร้าง 2560–2566)',
        countingRule: 'total_per_unit',
        academicYear: 2569,
        totalHours: 60,
        categoryCount: 5,
        subcategoryCount: 13,
        onAddCategory: () {},
      )));
      expect(find.text('5 หน่วย'), findsOneWidget);
      expect(find.text('ต่อหน่วย'), findsOneWidget);
      expect(find.text('ใช้กับรหัส ≤66'), findsOneWidget);
    });
  });

  group('หัวข้อ Talent พับได้', () {
    Widget tile({bool expanded = false}) => CriteriaGroupTile(
          name: _plo3.name,
          chip: 'PLO 3',
          countLabel: '3 รายการ',
          hours: criteriaGroupTargetHours(_plo3, const [_social]),
          rules: sharedTargetRules(_plo3, const [_social]),
          initiallyExpanded: expanded,
          children: [
            for (final (i, r) in _plo3.requirements.indexed)
              CriteriaRequirementRow(
                index: i,
                name: r.name,
                hours: r.requiredHours,
                mandatory: r.isMandatory,
                subtitle: requirementSubtitle(r),
              ),
          ],
        );

    testWidgets('พับอยู่: เห็นชื่อ PLO จำนวน ผลรวม และแถบกฎ แต่ไม่เห็นรายการ', (tester) async {
      await tester.pumpWidget(_wrap(tile()));
      expect(find.text('PLO 3'), findsOneWidget);
      expect(find.text('3 รายการ'), findsOneWidget);
      expect(find.text('รวม 20 ชม.'), findsOneWidget);
      expect(find.byKey(const ValueKey('shared-target-rule')), findsOneWidget);
      expect(find.text('ด้านการเป็นผู้ประกอบการ'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      await tester.tap(find.text(_plo3.name));
      await tester.pump();
      expect(find.text('ด้านการเป็นผู้ประกอบการ'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('ป้ายบังคับ = เหลือง (pending) · เลือก = เทา (neutral) เหมือนฟอร์มกิจกรรม', (tester) async {
      await tester.pumpWidget(_wrap(tile(expanded: true)));
      final chips = tester.widgetList<StatusChip>(find.byType(StatusChip)).toList();
      expect(chips.firstWhere((c) => c.label == 'บังคับ').palette, StatusPalette.pending);
      expect(chips.firstWhere((c) => c.label == 'เลือก').palette, StatusPalette.neutral);
      expect(find.text('16 ชม.'), findsNWidgets(2));
    });

    testWidgets('แถวสลับสี: แถวคู่มีพื้นอ่อน แถวคี่โปร่ง', (tester) async {
      await tester.pumpWidget(_wrap(tile(expanded: true)));
      Color? rowColor(int i) => ((tester
                  .widget<Container>(find
                      .descendant(of: find.byType(CriteriaRequirementRow).at(i), matching: find.byType(Container))
                      .first)
                  .decoration as BoxDecoration)
              .color);
      expect(rowColor(0), AppColors.fieldFill);
      expect(rowColor(1), isNull);
    });

    testWidgets('จอ 390px: หัวการ์ด + หัวข้อ + แถวรายการไม่ล้น', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final set = CriteriaSet(
        id: 2,
        code: '2567-regular',
        name: 'เกณฑ์ 2567 หลักสูตรปกติ (60 ชม.)',
        totalRequiredHours: 60,
        effectiveFromCohort: 2567,
        isSystem: true,
        groups: [_glocal, _plo3, _glocal],
      );
      await tester.pumpWidget(_wrap(Padding(
        padding: const EdgeInsets.all(16),
        child: CriteriaSetCard(
          header: systemCriteriaSectionHeader(set, allSets: [set], academicYear: 2569),
          children: [tile(expanded: true)],
        ),
      )));
      expect(tester.takeException(), isNull);
      // ป้ายล็อกจอแคบต้องอยู่ใต้ชื่อชุด ไม่ใช่เบียดขวา
      expect(tester.getRect(find.text('เกณฑ์ทางการ · อ่านอย่างเดียว')).right, lessThanOrEqualTo(390));
    });
  });
}
