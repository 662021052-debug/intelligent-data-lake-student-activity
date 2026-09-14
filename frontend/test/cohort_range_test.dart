import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/screens/criteria_set_forms.dart';
import 'package:activity_tracking_frontend/screens/hour_categories_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/cohort_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: SingleChildScrollView(child: child)));

CriteriaSet _set(int id, int cohort, {String programType = 'regular', String? name}) =>
    CriteriaSet(
      id: id,
      code: '$cohort-$programType',
      name: name ?? 'เกณฑ์ $cohort',
      programType: programType,
      effectiveFromCohort: cohort,
      groupedBy: cohort == 0 ? 'learning_unit' : 'talent',
      totalRequiredHours: 60,
    );

final _legacy = _set(1, 0, name: 'เกณฑ์เดิม (โครงสร้าง 2560–2566)');
final _s2567 = _set(2, 2567);
final _s2570 = _set(3, 2570);

String _codes(CriteriaSet set, List<CriteriaSet> all) => cohortRangeOf(set, all).codes;

void main() {
  group('ช่วงรุ่น = [ปีรุ่นของชุด .. ปีรุ่นของชุดถัดไป − 1]', () {
    test('ชุดเดียว: ไม่มีชุดถัดไป → "67 ขึ้นไป"', () {
      expect(_codes(_s2567, [_s2567]), '67 ขึ้นไป');
      expect(cohortRangeOf(_s2567, [_s2567]).pillLabel, 'ใช้กับรหัส 67 ขึ้นไป');
    });

    test('สองชุด (เดิม + 2567): เกณฑ์เดิม "≤66" · 2567 "67 ขึ้นไป"', () {
      final all = [_legacy, _s2567];
      expect(_codes(_legacy, all), '≤66');
      expect(cohortRangeOf(_legacy, all).pillLabel, 'ใช้กับรหัส ≤66');
      expect(_codes(_s2567, all), '67 ขึ้นไป');
    });

    test('สามชุด: เพิ่ม 2570 แล้ว 2567 หดเหลือ "67–69" เอง ชุดเดิมยัง "≤66"', () {
      final all = [_legacy, _s2567, _s2570];
      expect(_codes(_legacy, all), '≤66');
      expect(_codes(_s2567, all), '67–69');
      expect(cohortRangeOf(_s2567, all).pillLabel, 'ใช้กับรหัส 67–69');
      expect(_codes(_s2570, all), '70 ขึ้นไป');
    });

    test('ลำดับในรายการจาก API ไม่มีผล', () {
      expect(_codes(_s2567, [_s2570, _s2567, _legacy]), '67–69');
    });

    test('ชุดหลักสูตรต่อเนื่องไม่ตัดช่วงของหลักสูตรปกติ', () {
      final continuing = _set(9, 2570, programType: 'continuing');
      final all = [_legacy, _s2567, continuing];
      expect(_codes(_s2567, all), '67 ขึ้นไป');
      expect(_codes(continuing, all), '70 ขึ้นไป');
    });

    test('ชุดถัดไปห่างปีเดียว → รุ่นเดียว "67" ไม่ใช่ "67–67"', () {
      expect(_codes(_s2567, [_s2567, _set(4, 2568)]), '67');
    });

    test('ชุดขั้นล่างสุดชุดเดียว → ใช้กับทุกรุ่น', () {
      expect(cohortRangeOf(_legacy, [_legacy]).pillLabel, 'ใช้กับทุกรุ่น');
    });
  });

  group('ชั้นปีปัจจุบัน (ข้อมูลเสริมในวงเล็บ)', () {
    test('ปีการศึกษา 2569: 2567 ขึ้นไป = ปี 1–3 · ≤66 = ปี 4 ขึ้นไป', () {
      expect(const CohortRange(from: 2567).currentYearLevels(2569), 'ปัจจุบัน = ปี 1–3');
      expect(const CohortRange(from: 0, until: 2566).currentYearLevels(2569),
          'ปัจจุบัน = ปี 4 ขึ้นไป');
      expect(const CohortRange(from: 2567, until: 2569).currentYearLevels(2569),
          'ปัจจุบัน = ปี 1–3');
      expect(const CohortRange(from: 2570).currentYearLevels(2569),
          'ยังไม่มีนิสิตรุ่นนี้เข้าศึกษา');
    });

    test('ปีการศึกษาเริ่มมิถุนายน (ตามเวลาไทย)', () {
      expect(currentAcademicYear(DateTime.utc(2026, 9, 14)), 2569);
      expect(currentAcademicYear(DateTime.utc(2026, 5, 31)), 2568);
      // 31 พ.ค. 17:30 UTC = 1 มิ.ย. 00:30 เวลาไทย → ขึ้นปีการศึกษาใหม่แล้ว
      expect(currentAcademicYear(DateTime.utc(2026, 5, 31, 17, 30)), 2569);
    });
  });

  group('พรีวิวใต้ช่อง "ปีรุ่นที่เริ่มใช้"', () {
    String? preview(String text, {String programType = 'regular', CriteriaSet? editing,
            List<CriteriaSet>? sets}) =>
        cohortPreviewText(
          cohortText: text,
          programType: programType,
          sets: sets ?? [_legacy, _s2567],
          editing: editing,
        );

    test('ชุดใหม่ 2570 → บอกช่วงของตัวเอง + ชุด 2567 เหลือ 67–69', () {
      expect(preview('2570'), 'ชุดนี้จะใช้กับรหัส 70 ขึ้นไป และทำให้ชุด 2567 เหลือ 67–69');
    });

    test('แทรกระหว่างกลาง (2568 ขณะมี 2570) → มีปลายช่วงของตัวเองด้วย', () {
      expect(preview('2568', sets: [_legacy, _s2567, _s2570]),
          'ชุดนี้จะใช้กับรหัส 68–69 และทำให้ชุด 2567 เหลือ 67');
    });

    test('ปีรุ่นซ้ำในหลักสูตรเดียวกัน → เตือนก่อนบันทึก', () {
      expect(preview('2567'), contains('ใช้อยู่แล้ว'));
      expect(preview('2567', programType: 'continuing'), 'ชุดนี้จะใช้กับรหัส 67 ขึ้นไป');
    });

    test('ยังไม่ได้กรอก/กรอกผิด → ไม่โชว์พรีวิว', () {
      expect(preview(''), isNull);
      expect(preview('ปี 2570'), isNull);
      expect(preview('9999'), isNull);
    });

    test('โหมดแก้ไข: ไม่เปลี่ยนปี = ไม่กระทบชุดอื่น · เลื่อนปีขึ้น = ชุดก่อนหน้าขยาย', () {
      final all = [_legacy, _s2567, _s2570];
      expect(preview('2570', editing: _s2570, sets: all), 'ชุดนี้จะใช้กับรหัส 70 ขึ้นไป');
      expect(preview('2571', editing: _s2570, sets: all),
          'ชุดนี้จะใช้กับรหัส 71 ขึ้นไป และทำให้ชุด 2567 ขยายเป็น 67–70');
    });

    testWidgets('พิมพ์ปีในฟอร์มแล้วพรีวิวขึ้นสด ๆ', (tester) async {
      await tester.pumpWidget(_wrap(CriteriaSetFormDialog(existingSets: [_legacy, _s2567])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cohort-preview')), findsNothing);

      await tester.enterText(find.byType(TextFormField).at(3), '2570');
      await tester.pump();
      expect(find.text('ชุดนี้จะใช้กับรหัส 70 ขึ้นไป และทำให้ชุด 2567 เหลือ 67–69'),
          findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(3), '2575');
      await tester.pump();
      expect(find.text('ชุดนี้จะใช้กับรหัส 75 ขึ้นไป และทำให้ชุด 2567 เหลือ 67–74'),
          findsOneWidget);
    });
  });

  group('หัวการ์ดบนหน้าเกณฑ์', () {
    String pill(WidgetTester tester) => tester
        .widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('cohort-range-pill')),
          matching: find.byType(Text),
        ))
        .data!;

    testWidgets('ชุด 2567 ตอนยังไม่มีชุด 2570 → "ใช้กับรหัส 67 ขึ้นไป (ปัจจุบัน = ปี 1–3)"',
        (tester) async {
      await tester.pumpWidget(_wrap(systemCriteriaSectionHeader(
        _s2567,
        allSets: [_legacy, _s2567],
        academicYear: 2569,
      )));
      expect(pill(tester), 'ใช้กับรหัส 67 ขึ้นไป');
      expect(find.text('เข้าศึกษาปี 2567 ขึ้นไป (ปัจจุบัน = ปี 1–3)'), findsOneWidget);
    });

    testWidgets('เพิ่มชุด 2570 แล้วป้ายชุด 2567 เปลี่ยนเป็น "67–69" เอง', (tester) async {
      await tester.pumpWidget(_wrap(systemCriteriaSectionHeader(
        _s2567,
        allSets: [_legacy, _s2567, _s2570],
        academicYear: 2569,
      )));
      expect(pill(tester), 'ใช้กับรหัส 67–69');
      expect(find.text('เข้าศึกษาปี 2567–2569 (ปัจจุบัน = ปี 1–3)'), findsOneWidget);
    });

    testWidgets('ชุดของผู้ดูแล 2570 → ป้าย "70 ขึ้นไป" + หลักสูตร', (tester) async {
      await tester.pumpWidget(_wrap(customCriteriaSectionHeader(
        _s2570,
        allSets: [_legacy, _s2567, _s2570],
        academicYear: 2569,
        onEdit: () {},
        onDelete: () {},
        onAddTalent: () {},
        onAddGroup: () {},
        onAddRequirement: () {},
      )));
      expect(pill(tester), 'ใช้กับรหัส 70 ขึ้นไป');
      expect(find.text('เข้าศึกษาปี 2570 ขึ้นไป (ยังไม่มีนิสิตรุ่นนี้เข้าศึกษา) · หลักสูตรปกติ'),
          findsOneWidget);
    });

    test('บรรทัดช่วยจำท้ายหน้าใช้ตัวอย่างจากชุดจริง', () {
      final hint = criteriaRangeHint([_legacy, _s2567], 2569);
      expect(hint, contains('ปีรุ่นที่เริ่มใช้ = 2570'));
      expect(hint, contains('ระบบจะปรับชุด 2567 เหลือ 67–69 ให้อัตโนมัติ'));
      expect(hint, contains('รหัส 70 ขึ้นไป เข้าชุดใหม่เอง'));
      expect(hint, contains('ไม่ต้องแก้ชุดเก่า'));

      // มีชุด 2570 แล้ว → ตัวอย่างขยับเป็น 2571 และชุดที่หดคือ 2570
      final later = criteriaRangeHint([_legacy, _s2567, _s2570], 2569);
      expect(later, contains('ปีรุ่นที่เริ่มใช้ = 2571'));
      expect(later, contains('ชุด 2570 เหลือ 70'));
    });
  });
}
