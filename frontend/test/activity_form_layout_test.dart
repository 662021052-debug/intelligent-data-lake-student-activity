import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/models/hour_category.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/requirement_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// งานที่ 1 ของ PROMPT_Activity_and_Criteria_UI — ฟอร์มกิจกรรม: เกณฑ์เป็นพระเอก ประเภทเป็นป้ายรอง
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

const _set = CriteriaSet(
  id: 1,
  code: '2567-regular',
  name: 'เกณฑ์ 2567 หลักสูตรปกติ',
  academicYear: 2567,
  totalRequiredHours: 60,
  groupedBy: 'talent',
  groups: [
    CriteriaGroup(
      key: 'talent:2',
      name: 'TSU Communication Talent',
      subtitle: 'PLO 2',
      requirements: [
        CriteriaRequirement(id: 31, name: 'ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล', requiredHours: 3),
        CriteriaRequirement(id: 32, name: 'ทักษะการใช้ภาษาเพื่อการสื่อสาร', requiredHours: 5),
      ],
    ),
  ],
);

final _categories = [
  HourCategory(
    id: 1,
    name: 'ใฝ่เรียนรู้ตลอดชีวิต',
    requiredHours: 30,
    subcategories: [HourSubcategory(id: 7, name: 'กิจกรรม ICT 1', requiredHours: 10)],
  ),
];

Activity _existing({String type = 'วิชาการ', List<int> requirementIds = const [31], double hours = 3}) =>
    Activity(
      id: 9,
      name: 'อบรมความปลอดภัยไซเบอร์',
      activityType: type,
      hours: hours,
      maxParticipants: 50,
      startAt: DateTime(2026, 12, 1, 9),
      location: 'หอประชุม',
      requirementIds: requirementIds,
    );

Future<void> _pump(
  WidgetTester tester, {
  Activity? existing,
  List<CriteriaSet> sets = const [_set],
  Size size = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(ActivityFormDialog(existing: existing, categories: _categories, criteriaSets: sets)));
  await tester.pumpAndSettle();
}

final Finder _block = find.byKey(const ValueKey('activity-criteria-block'));
Finder _inBlock(Finder f) => find.descendant(of: _block, matching: f);
Finder _field(String label) => find.ancestor(of: find.text(label), matching: find.byType(TextField));
List<ChoiceChip> _chips(WidgetTester tester) => tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
String _chipText(ChoiceChip chip) => (chip.label as Text).data!;

void main() {
  group('ลำดับและน้ำหนักของช่อง', () {
    testWidgets('ชื่อ → บล็อกเกณฑ์ → ชั่วโมง/จำนวนรับ → วันเวลา/สถานที่ → ประเภท', (tester) async {
      await _pump(tester);
      double top(Finder f) => tester.getTopLeft(f).dy;

      final name = top(find.text('ชื่อกิจกรรม'));
      final block = top(_block);
      final hours = top(find.text('ชั่วโมงที่ได้รับ'));
      final seats = top(find.text('จำนวนที่รับ'));
      // เทียบกรอบของช่อง ไม่ใช่ตัว label — ช่องวันเวลามีค่าอยู่แล้ว label จึงลอยขึ้นคนละระดับกับช่องว่าง
      final date = top(find.ancestor(of: find.text('วันเวลาเริ่มกิจกรรม'), matching: find.byType(InputDecorator)).first);
      final place = top(_field('สถานที่'));
      final type = top(find.textContaining('ประเภทกิจกรรม'));

      expect(name, lessThan(block));
      expect(block, lessThan(hours));
      expect(hours, lessThan(date));
      expect(date, lessThan(type));
      // จอกว้าง: ชั่วโมงคู่จำนวนรับ และวันเวลาคู่สถานที่ อยู่แถวเดียวกัน
      expect(hours, moreOrLessEquals(seats, epsilon: 2));
      expect(date, moreOrLessEquals(place, epsilon: 2));
    });

    testWidgets('บล็อกเกณฑ์มีหัวข้อ + คำอธิบาย และรวมทุกทางที่ให้ชั่วโมงไว้ข้างใน', (tester) async {
      await _pump(tester);

      expect(_inBlock(find.textContaining('นับเข้าเกณฑ์ชั่วโมง')), findsOneWidget);
      expect(
        _inBlock(find.text(
            'ตัวนี้คือสิ่งที่กำหนดว่านิสิตได้ชั่วโมงหมวดไหน · เลือกได้หลายข้อ ชั่วโมงจะเข้าให้ทุกข้อที่เลือก')),
        findsOneWidget,
      );
      expect(_inBlock(find.byType(RequirementPicker)), findsOneWidget);
      expect(_inBlock(find.text('หมวดชั่วโมงโครงเดิม (ไม่บังคับ)')), findsOneWidget);
      // หัวข้อเดิมของ picker ไม่ซ้ำกับหัวบล็อก
      expect(find.text('รายการเกณฑ์ที่กิจกรรมนี้นับชั่วโมงให้'), findsNothing);
    });

    testWidgets('ช่องประเภทบอกชัดว่าเป็นแค่ป้าย และไม่ใช่ dropdown แล้ว', (tester) async {
      await _pump(tester);

      expect(find.textContaining('ป้ายไว้ค้นหา/กรอง ไม่เกี่ยวกับการนับชั่วโมง'), findsOneWidget);
      expect(_chips(tester).map(_chipText), ['จิตอาสา', 'กีฬา', 'วิชาการ', 'ศิลปวัฒนธรรม', 'อบรม/สัมมนา']);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(_inBlock(find.textContaining('ประเภทกิจกรรม')), findsNothing, reason: 'ประเภทไม่อยู่ในบล็อกเกณฑ์');
    });
  });

  group('ประเภท = chip เลือก ไม่มีค่าเริ่มต้นติดมาเงียบ ๆ', () {
    testWidgets('สร้างใหม่: ยังไม่มีชิปไหนถูกเลือก · กดบันทึกแล้วเตือนให้เลือกประเภท', (tester) async {
      await _pump(tester);
      expect(_chips(tester).where((c) => c.selected), isEmpty);

      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(find.text('เลือกประเภทกิจกรรม'), findsOneWidget);
      // ตรวจพร้อมกันทุกข้อ: ข้อเกณฑ์ที่ขาดก็ขึ้นในรอบเดียวกัน
      expect(find.textContaining('กรุณาเลือกรายการเกณฑ์อย่างน้อยหนึ่งรายการ'), findsOneWidget);
    });

    testWidgets('กดชิปแล้วเลือกได้ทีละค่า', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('กีฬา'));
      await tester.pumpAndSettle();
      expect(_chips(tester).where((c) => c.selected).map(_chipText), ['กีฬา']);

      await tester.tap(find.text('อบรม/สัมมนา'));
      await tester.pumpAndSettle();
      expect(_chips(tester).where((c) => c.selected).map(_chipText), ['อบรม/สัมมนา']);
      expect(find.text('เลือกประเภทกิจกรรม'), findsNothing);
    });

    testWidgets('แก้ไข: ประเภทเดิมถูกเลือกไว้', (tester) async {
      await _pump(tester, existing: _existing(type: 'จิตอาสา'));
      expect(_chips(tester).where((c) => c.selected).map(_chipText), ['จิตอาสา']);
    });

    testWidgets('แก้ไข: ประเภทเดิมที่ไม่อยู่ใน 5 ค่า ยังโชว์และเลือกคืนได้ ไม่หายเงียบ ๆ', (tester) async {
      await _pump(tester, existing: _existing(type: 'อบรม'));
      expect(_chips(tester).length, 6);
      expect(_chips(tester).where((c) => c.selected).map(_chipText), ['อบรม']);

      await tester.tap(find.text('กีฬา'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('อบรม'));
      await tester.pumpAndSettle();
      expect(_chips(tester).where((c) => c.selected).map(_chipText), ['อบรม']);
    });

    test('ตัวเลือกประเภท = 5 ค่าเดิม + ค่าเดิมที่ไม่อยู่ในรายการ', () {
      const five = ['จิตอาสา', 'กีฬา', 'วิชาการ', 'ศิลปวัฒนธรรม', 'อบรม/สัมมนา'];
      expect(activityTypeChoices(null), five);
      expect(activityTypeChoices(''), five);
      expect(activityTypeChoices('วิชาการ'), five);
      expect(activityTypeChoices('อบรม'), [...five, 'อบรม']);
    });
  });

  group('pill ของรายการเกณฑ์ที่เลือก', () {
    testWidgets('แก้ไข: รายการเดิมขึ้นเป็น pill พร้อมเส้นทางชุด › กลุ่ม และชั่วโมง', (tester) async {
      await _pump(tester, existing: _existing(hours: 3));
      final pill = find.byKey(const ValueKey('requirement-pill-31'));

      expect(pill, findsOneWidget);
      expect(find.descendant(of: pill, matching: find.text('ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล')),
          findsOneWidget);
      expect(find.descendant(of: pill, matching: find.text('เกณฑ์ 2567 หลักสูตรปกติ › TSU Communication Talent (PLO 2)')),
          findsOneWidget);
      expect(find.descendant(of: pill, matching: find.text('3 ชม.')), findsOneWidget);
      // มีรายการแล้ว กล่องรายการพับไว้
      expect(find.byType(RequirementPicker), findsNothing);
    });

    testWidgets('ชั่วโมงใน pill เปลี่ยนตามช่องชั่วโมงทันที', (tester) async {
      await _pump(tester, existing: _existing(hours: 3));
      await tester.enterText(_field('ชั่วโมงที่ได้รับ'), '4.5');
      await tester.pumpAndSettle();

      expect(find.descendant(of: find.byKey(const ValueKey('requirement-pill-31')), matching: find.text('4.5 ชม.')),
          findsOneWidget);
    });

    testWidgets('กด ✕ แล้วรายการหลุดจาก pill', (tester) async {
      await _pump(tester, existing: _existing(requirementIds: const [31, 32]));
      expect(find.byKey(const ValueKey('requirement-pill-32')), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('requirement-pill-32')),
        matching: find.byTooltip('เอารายการนี้ออก'),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('requirement-pill-32')), findsNothing);
      expect(find.byKey(const ValueKey('requirement-pill-31')), findsOneWidget);
    });

    testWidgets('สร้างใหม่: กล่องรายการกางไว้ · ปุ่มสลับซ่อน/เพิ่มเกณฑ์ได้', (tester) async {
      await _pump(tester);
      expect(find.byType(RequirementPicker), findsOneWidget);

      await tester.tap(find.text('ซ่อนรายการเกณฑ์'));
      await tester.pumpAndSettle();
      expect(find.byType(RequirementPicker), findsNothing);

      await tester.tap(find.text('เพิ่มเกณฑ์ที่นับเข้า'));
      await tester.pumpAndSettle();
      expect(find.byType(RequirementPicker), findsOneWidget);
    });

    test('เส้นทางรายการเกณฑ์ = ชื่อชุด › ชื่อกลุ่ม (PLO)', () {
      final paths = requirementPaths(const [_set]);
      expect(paths[31]!.name, 'ความรู้ ความเข้าใจ และการใช้เทคโนโลยีดิจิทัล');
      expect(paths[31]!.path, 'เกณฑ์ 2567 หลักสูตรปกติ › TSU Communication Talent (PLO 2)');
      expect(paths[99], isNull);
    });
  });

  group('payload ที่ส่ง backend ไม่เปลี่ยน', () {
    test('คีย์และรูปแบบเหมือนเดิมทุกตัว', () {
      final body = activityFormPayload(
        name: 'อบรม',
        activityType: 'วิชาการ',
        subcategoryId: null,
        requirementIds: {32, 31},
        hours: 3,
        isRequired: false,
        maxParticipants: 50,
        startAt: DateTime(2026, 10, 14, 9),
        location: 'หอประชุม',
      );

      expect(body.keys.toSet(), {
        'name', 'activity_type', 'subcategory_id', 'requirement_ids', 'hours',
        'is_required', 'max_participants', 'start_at', 'location',
      });
      expect(body['activity_type'], 'วิชาการ');
      expect(body['requirement_ids'], [31, 32], reason: 'เรียงเหมือนเดิม');
      expect(body['start_at'], '2026-10-14T09:00:00.000');
      expect(body['subcategory_id'], isNull);
    });
  });

  testWidgets('จอ 360px: ช่องซ้อนเป็นแถวเดียว ไม่ล้น แม้มี pill และกางกล่องรายการ', (tester) async {
    await _pump(tester, existing: _existing(requirementIds: const [31, 32]), size: const Size(360, 740));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('เพิ่มเกณฑ์ที่นับเข้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มเกณฑ์ที่นับเข้า'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('จำนวนที่รับ'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('จำนวนที่รับ')).dy,
        greaterThan(tester.getTopLeft(find.text('ชั่วโมงที่ได้รับ')).dy),
        reason: 'จอแคบซ้อนเป็นแถวเดียวต่อช่อง');
  });
}
