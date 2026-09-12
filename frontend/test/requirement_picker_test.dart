import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/models/hour_category.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/requirement_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ต้องใช้ธีมจริง — ธีมของแอปตั้ง splashFactory เป็น InkRipple ส่วนดีฟอลต์ M3
// เป็น InkSparkle ที่ต้องโหลด shader asset ซึ่งไม่มีตอนรัน --no-test-assets
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

const _talentSet = CriteriaSet(
  id: 1,
  code: '2567-regular',
  name: 'เกณฑ์ 2567 หลักสูตรปกติ',
  academicYear: 2567,
  totalRequiredHours: 60,
  groupedBy: 'talent',
  groups: [
    CriteriaGroup(
      key: 'talent:1',
      name: 'TSU Glocal Talent',
      subtitle: 'PLO 1',
      requirements: [
        CriteriaRequirement(
          id: 14,
          name: 'กิจกรรมปฐมนิเทศนิสิต',
          requiredHours: 4,
          isMandatory: true,
          learningUnitName: 'พัฒนาทักษะชีวิต',
        ),
        CriteriaRequirement(id: 16, name: 'การคิด วิจารณญาณ และการแก้ปัญหา', requiredHours: 3),
      ],
    ),
    CriteriaGroup(
      key: 'talent:3',
      name: 'TSU Social Talent',
      subtitle: 'PLO 3',
      requirements: [
        CriteriaRequirement(
          id: 22,
          name: 'ด้านการสร้างนวัตกรรมสังคม',
          requiredHours: 8,
          groupName: 'กลุ่ม Social 16 ชม.',
        ),
      ],
    ),
  ],
);

const _legacySet = CriteriaSet(
  id: 2,
  code: 'legacy-2566',
  name: 'เกณฑ์เดิม (โครงสร้าง 2560–2566)',
  academicYear: 2566,
  totalRequiredHours: 60,
  groupedBy: 'learning_unit',
  groups: [
    CriteriaGroup(
      key: 'unit:1',
      name: 'พัฒนาทักษะชีวิต',
      subtitle: 'หน่วยที่ 1',
      requirements: [
        CriteriaRequirement(id: 40, name: 'กิจกรรมเสริมสร้างคุณค่าแห่งตน', requiredHours: 8),
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

/// picker ที่จำค่าที่เลือกไว้เองได้ เหมือนตอนอยู่ในฟอร์มจริง
class _PickerHarness extends StatefulWidget {
  const _PickerHarness({this.initial = const {}, this.maxListHeight = 260});

  final Set<int> initial;

  /// เทสต์ที่ต้องเห็นทุกกลุ่มพร้อมกันขยายกล่องให้สูงพอ แทนการเลื่อนทีละขั้น
  final double maxListHeight;

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  late Set<int> selected = {...widget.initial};

  @override
  Widget build(BuildContext context) => RequirementPicker(
        criteriaSets: const [_talentSet, _legacySet],
        selected: selected,
        onChanged: (ids) => setState(() => selected = ids),
        maxListHeight: widget.maxListHeight,
      );
}

void main() {
  group('ช่องเลือกรายการเกณฑ์', () {
    testWidgets('จัดกลุ่มตามชุดเกณฑ์: 2567 เป็น Talent/PLO · ชุดเดิมเป็นหน่วยการเรียนรู้',
        (tester) async {
      await tester.pumpWidget(_wrap(const _PickerHarness()));
      await tester.pumpAndSettle();

      expect(find.text('เกณฑ์ 2567 หลักสูตรปกติ'), findsOneWidget);
      expect(find.text('เกณฑ์เดิม (โครงสร้าง 2560–2566)'), findsOneWidget);
      expect(find.text('จัดกลุ่มตามTalent / PLO · รวม 60 ชม.'), findsOneWidget);
      expect(find.text('จัดกลุ่มตามหน่วยการเรียนรู้ · รวม 60 ชม.'), findsOneWidget);

      expect(find.text('TSU Glocal Talent (PLO 1)'), findsOneWidget);
      expect(find.text('TSU Social Talent (PLO 3)'), findsOneWidget);
      expect(find.text('พัฒนาทักษะชีวิต (หน่วยที่ 1)'), findsOneWidget);
    });

    testWidgets('กลุ่มพับไว้ก่อน กดหัวข้อแล้วจึงเห็นรายการข้างใน', (tester) async {
      await tester.pumpWidget(_wrap(const _PickerHarness()));
      await tester.pumpAndSettle();

      expect(find.text('กิจกรรมปฐมนิเทศนิสิต'), findsNothing);

      await tester.tap(find.text('TSU Glocal Talent (PLO 1)'));
      await tester.pumpAndSettle();

      expect(find.text('กิจกรรมปฐมนิเทศนิสิต'), findsOneWidget);
      expect(find.text('การคิด วิจารณญาณ และการแก้ปัญหา'), findsOneWidget);
      // เป้าชั่วโมง/บังคับ/หน่วย บอกไว้ใต้ชื่อ เพื่อให้เลือกได้ถูกโดยไม่ต้องเปิดเอกสารเกณฑ์
      expect(find.text('เป้า 4 ชม. · บังคับ · พัฒนาทักษะชีวิต'), findsOneWidget);
    });

    testWidgets('เลือกได้หลายรายการข้ามกลุ่มและข้ามชุดเกณฑ์', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const _PickerHarness(maxListHeight: 900)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TSU Glocal Talent (PLO 1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('กิจกรรมปฐมนิเทศนิสิต'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('พัฒนาทักษะชีวิต (หน่วยที่ 1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('กิจกรรมเสริมสร้างคุณค่าแห่งตน'));
      await tester.pumpAndSettle();

      final state = tester.state<_PickerHarnessState>(find.byType(_PickerHarness));
      expect(state.selected, {14, 40});
      expect(find.text('เลือกแล้ว 2 รายการ'), findsOneWidget);
      // จำนวนที่เลือกในแต่ละกลุ่มขึ้นที่หัวข้อ จะได้เห็นแม้ตอนพับ
      expect(find.text('เลือก 1'), findsNWidgets(2));
    });

    testWidgets('ติ๊กออกแล้วรายการนั้นหลุดจากที่เลือก และล้างทั้งหมดได้', (tester) async {
      await tester.pumpWidget(_wrap(const _PickerHarness(initial: {14, 22})));
      await tester.pumpAndSettle();

      // โหมดแก้ไข: กลุ่มที่มีรายการถูกเลือกไว้ต้องกางมาให้เลย ไม่ต้องไล่หาเอง
      expect(find.text('กิจกรรมปฐมนิเทศนิสิต'), findsOneWidget);
      expect(find.text('ด้านการสร้างนวัตกรรมสังคม'), findsOneWidget);
      expect(find.text('เลือกแล้ว 2 รายการ'), findsOneWidget);

      await tester.tap(find.text('กิจกรรมปฐมนิเทศนิสิต'));
      await tester.pumpAndSettle();
      expect(tester.state<_PickerHarnessState>(find.byType(_PickerHarness)).selected, {22});

      await tester.tap(find.text('ล้างทั้งหมด'));
      await tester.pumpAndSettle();
      expect(tester.state<_PickerHarnessState>(find.byType(_PickerHarness)).selected, isEmpty);
    });

    testWidgets('รายการที่แชร์เป้าชั่วโมงกับตัวอื่นบอกไว้ให้เห็น', (tester) async {
      await tester.pumpWidget(_wrap(const _PickerHarness(initial: {22})));
      await tester.pumpAndSettle();

      expect(find.textContaining('รวมกับกลุ่ม Social 16 ชม.'), findsOneWidget);
    });

    testWidgets('ยังไม่มีชุดเกณฑ์ในระบบ ก็ไม่พังทั้งฟอร์ม', (tester) async {
      await tester.pumpWidget(_wrap(
        RequirementPicker(criteriaSets: const [], selected: const {}, onChanged: (_) {}),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('ยังไม่มีชุดเกณฑ์ในระบบ'), findsOneWidget);
    });
  });

  group('ฟอร์มกิจกรรมกับรายการเกณฑ์', () {
    testWidgets('มีชุดเกณฑ์แล้ว หมวดชั่วโมงโครงเดิมไม่บังคับและไม่ถูกเลือกไว้ล่วงหน้า',
        (tester) async {
      await tester.pumpWidget(_wrap(ActivityFormDialog(
        categories: _categories,
        criteriaSets: const [_talentSet],
      )));
      await tester.pumpAndSettle();

      expect(find.byType(RequirementPicker), findsOneWidget);
      expect(find.text('หมวดชั่วโมงโครงเดิม (ไม่บังคับ)'), findsOneWidget);
      // ไม่เดาหมวดของรุ่นเก่าให้ ไม่งั้นกิจกรรมจะติดหมวดที่ผู้ใช้ไม่ได้ตั้งใจเลือก
      expect(find.text('กิจกรรม ICT 1'), findsNothing);
    });

    testWidgets('ไม่มีชุดเกณฑ์ ฟอร์มยังบังคับเลือกหมวดชั่วโมงเหมือนเดิม', (tester) async {
      await tester.pumpWidget(_wrap(ActivityFormDialog(categories: _categories)));
      await tester.pumpAndSettle();

      expect(find.text('หมวดชั่วโมง'), findsOneWidget);
      expect(find.text('กิจกรรม ICT 1'), findsOneWidget);
    });

    testWidgets('ไม่เลือกอะไรเลยแล้วกดบันทึก ต้องเตือน ไม่ยิง API', (tester) async {
      await tester.pumpWidget(_wrap(ActivityFormDialog(
        categories: _categories,
        criteriaSets: const [_talentSet],
      )));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(of: find.text('ชื่อกิจกรรม'), matching: find.byType(TextField)),
        'อบรมทักษะดิจิทัล',
      );
      await tester.enterText(
        find.ancestor(of: find.text('สถานที่'), matching: find.byType(TextField)),
        'อาคารเรียนรวม 1',
      );
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.textContaining('กรุณาเลือกรายการเกณฑ์อย่างน้อยหนึ่งรายการ'), findsOneWidget);
    });

    testWidgets('โหมดแก้ไขติ๊กรายการเดิมของกิจกรรมไว้ให้', (tester) async {
      final existing = Activity(
        id: 5,
        name: 'ค่ายอาสาปี 2568',
        activityType: 'จิตอาสา',
        hours: 4,
        maxParticipants: 50,
        startAt: DateTime(2026, 12, 1, 9, 0),
        location: 'ห้อง SC101',
        requirementIds: const [16],
      );

      await tester.pumpWidget(_wrap(ActivityFormDialog(
        existing: existing,
        categories: _categories,
        criteriaSets: const [_talentSet],
      )));
      await tester.pumpAndSettle();

      expect(find.text('เลือกแล้ว 1 รายการ'), findsOneWidget);
      final checkbox = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('การคิด วิจารณญาณ และการแก้ปัญหา'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.value, isTrue);
    });

    testWidgets('ฟอร์มพร้อมรายการเกณฑ์ไม่ล้นจอที่ 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(ActivityFormDialog(
        categories: _categories,
        criteriaSets: const [_talentSet, _legacySet],
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TSU Glocal Talent (PLO 1)'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('ป้ายเกณฑ์ในตารางกิจกรรม', () {
    Activity activity({List<int> requirementIds = const [], int? subcategoryId}) => Activity(
          id: 1,
          name: 'กิจกรรม',
          activityType: 'อบรม',
          maxParticipants: 10,
          startAt: DateTime(2026, 12, 1),
          location: 'ห้อง A',
          subcategoryId: subcategoryId,
          requirementIds: requirementIds,
        );

    test('ผูกรายการเกณฑ์ไว้ → แสดงชื่อรายการ ไม่ใช่ขีด', () {
      expect(
        activityCriteriaLabel(_categories, const [_talentSet], activity(requirementIds: [14])),
        'กิจกรรมปฐมนิเทศนิสิต',
      );
      expect(
        activityCriteriaLabel(_categories, const [_talentSet], activity(requirementIds: [14, 16])),
        'กิจกรรมปฐมนิเทศนิสิต +1',
      );
    });

    test('กิจกรรมโครงเดิมยังแสดงเป็นหมวดแม่ › หมวดย่อย', () {
      expect(
        activityCriteriaLabel(_categories, const [_talentSet], activity(subcategoryId: 7)),
        'ใฝ่เรียนรู้ตลอดชีวิต › กิจกรรม ICT 1',
      );
      expect(activityCriteriaLabel(_categories, const [], activity()), '-');
    });

    test('ยังโหลดชุดเกณฑ์ไม่เสร็จ ก็ยังบอกได้ว่าผูกไว้กี่รายการ', () {
      expect(
        activityCriteriaLabel(_categories, const [], activity(requirementIds: [14, 16])),
        '2 รายการเกณฑ์',
      );
    });
  });
}
