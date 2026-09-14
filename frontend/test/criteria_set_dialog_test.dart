import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/screens/criteria_set_forms.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

const _legacy = CriteriaSet(id: 1, code: 'legacy-2566', name: 'เกณฑ์เดิม', effectiveFromCohort: 0);
const _s2567 = CriteriaSet(id: 2, code: '2567-regular', name: 'เกณฑ์ 2567', effectiveFromCohort: 2567);

Finder _block(String key) => find.byKey(ValueKey(key));
Finder _inBlock(String key, Finder matching) => find.descendant(of: _block(key), matching: matching);

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('payload ของ POST/PUT /criteria-sets เหมือนเดิมทุกคีย์', () {
    test('ครบ 7 คีย์ ชนิดข้อมูลเดิม ตัดช่องว่างให้', () {
      final body = criteriaSetPayload(
        code: ' 2570-regular ',
        name: ' เกณฑ์ 2570 ',
        academicYear: '2570',
        programType: 'continuing',
        cohort: ' 2570',
        hours: '60',
        countingRule: 'total_per_unit',
      );
      expect(body.keys.toSet(), {
        'code',
        'name',
        'academic_year',
        'effective_from_cohort',
        'program_type',
        'total_required_hours',
        'counting_rule',
      });
      expect(body, {
        'code': '2570-regular',
        'name': 'เกณฑ์ 2570',
        'academic_year': 2570,
        'program_type': 'continuing',
        'effective_from_cohort': 2570,
        'total_required_hours': 60.0,
        'counting_rule': 'total_per_unit',
      });
    });
  });

  group('ไดอะล็อกเพิ่มชุดเกณฑ์ใหม่', () {
    testWidgets('บล็อกเรียง: พระเอก "ชุดนี้ใช้กับนิสิตรุ่นไหน" → ข้อมูลชุด → การนับชั่วโมง', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog(existingSets: [_legacy, _s2567])));
      await tester.pumpAndSettle();

      final ys = [
        tester.getTopLeft(_block('criteria-set-audience-block')).dy,
        tester.getTopLeft(_block('criteria-set-info-block')).dy,
        tester.getTopLeft(_block('criteria-set-counting-block')).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(tester.widget<FormBlock>(_block('criteria-set-audience-block')).hero, isTrue);
      expect(tester.widget<FormBlock>(_block('criteria-set-info-block')).hero, isFalse);

      expect(find.text('ชุดนี้ใช้กับนิสิตรุ่นไหน'), findsOneWidget);
      expect(_inBlock('criteria-set-audience-block', find.byKey(const ValueKey('criteria-set-cohort'))),
          findsOneWidget);
      expect(_inBlock('criteria-set-info-block', find.byKey(const ValueKey('criteria-set-name'))), findsOneWidget);
      expect(_inBlock('criteria-set-counting-block', find.byKey(const ValueKey('criteria-set-hours'))),
          findsOneWidget);
      expect(find.textContaining('ต่อรายการ = ต้องครบทุกรายการ · ต่อหน่วย = ดูยอดรวม'), findsOneWidget);
    });

    testWidgets('รหัสชุดคู่กลุ่มหลักสูตร · ชั่วโมงคู่วิธีนับ (2 คอลัมน์) พร้อม help "ห้ามซ้ำ"', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog()));
      await tester.pumpAndSettle();

      double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      double left(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dx;
      expect(top('criteria-set-code'), top('criteria-set-program-type'));
      expect(left('criteria-set-code'), lessThan(left('criteria-set-program-type')));
      expect(top('criteria-set-hours'), top('criteria-set-counting-rule'));
      expect(find.text('ใช้อ้างถึงชุดนี้ในระบบ ห้ามซ้ำ'), findsOneWidget);
      // dropdown เป็นข้อความไทยเต็ม ไม่ใช่ค่าเบื้องหลัง
      expect(find.text('หลักสูตรปกติ'), findsOneWidget);
      expect(find.text('ครบตามชั่วโมงของแต่ละรายการ'), findsOneWidget);
      expect(find.text('regular'), findsNothing);
    });

    testWidgets('ปุ่มหลักตอนสร้าง = "บันทึก แล้วเพิ่มรายการเกณฑ์"', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog()));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, kSaveAndAddRequirementLabel), findsOneWidget);
    });

    testWidgets('พรีวิวช่วงรุ่นขึ้นจริงในบล็อกพระเอกเมื่อพิมพ์ปีที่ถูกต้อง และคิดใหม่เมื่อเปลี่ยนกลุ่มหลักสูตร',
        (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog(existingSets: [_legacy, _s2567])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cohort-preview')), findsNothing, reason: 'ยังไม่ได้พิมพ์');

      await tester.enterText(find.byKey(const ValueKey('criteria-set-cohort')), '2570');
      await tester.pump();
      const expected = 'ชุดนี้จะใช้กับรหัส 70 ขึ้นไป และทำให้ชุด 2567 เหลือ 67–69';
      expect(_inBlock('criteria-set-audience-block', find.text(expected)), findsOneWidget);

      // หลักสูตรต่อเนื่องไม่มีชุดอื่น → ไม่กระทบชุด 2567
      await tester.tap(find.byKey(const ValueKey('criteria-set-program-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('หลักสูตรต่อเนื่อง').last);
      await tester.pumpAndSettle();
      expect(find.text('ชุดนี้จะใช้กับรหัส 70 ขึ้นไป'), findsOneWidget);

      // ปีผิดช่วง → พรีวิวหาย (validator ยังเตือนตอนกดบันทึก)
      await tester.enterText(find.byKey(const ValueKey('criteria-set-cohort')), '99999');
      await tester.pump();
      expect(find.byKey(const ValueKey('cohort-preview')), findsNothing);
    });

    testWidgets('ปีรุ่นซ้ำในหลักสูตรเดียวกัน → เตือนในพรีวิว', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog(existingSets: [_legacy, _s2567])));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('criteria-set-cohort')), '2567');
      await tester.pump();
      expect(find.textContaining('ใช้อยู่แล้วในกลุ่มหลักสูตรนี้'), findsOneWidget);
    });

    testWidgets('กดบันทึกตอนว่าง: validation เดิมยังเตือนครบทุกช่องบังคับ', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('criteria-set-hours')), '0');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('กรอกปี พ.ศ. เช่น 2570'), findsNWidgets(2), reason: 'ปีรุ่น + ปีหลักสูตร');
      expect(find.text('กรอกข้อมูล'), findsNWidgets(2), reason: 'ชื่อ + รหัสชุด');
      expect(find.text('ต้องมากกว่า 0'), findsOneWidget);
    });

    testWidgets('จอ 390px: ไม่ล้น และช่องคู่เรียงลงเป็นคอลัมน์', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(const CriteriaSetFormDialog(existingSets: [_legacy, _s2567])));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('criteria-set-program-type'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const ValueKey('criteria-set-code'))).dy),
      );
    });
  });
}
