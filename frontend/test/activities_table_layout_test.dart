import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/screens/app_shell.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/format.dart';
import 'package:activity_tracking_frontend/widgets/app_buttons.dart';
import 'package:activity_tracking_frontend/widgets/app_card.dart';
import 'package:activity_tracking_frontend/widgets/app_table_cells.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _labelOf(DataColumn column) => (column.label as ActivityColumnLabel).text;

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

const _allLabels = [
  'ชื่อกิจกรรม',
  'วันเวลา',
  'สถานที่',
  'ประเภท',
  'นับเข้าหมวด',
  'ชั่วโมงที่ได้',
  'สถานะอนุมัติ',
  'จัดการ',
];

Activity _activity(
  int id, {
  String? name,
  bool required = false,
  String status = 'approved',
  bool hidden = false,
  String location = 'หอประชุมใหญ่',
}) =>
    Activity(
      id: id,
      name: name ?? 'กิจกรรมทดสอบลำดับที่ $id',
      activityType: 'อบรม/สัมมนา',
      hours: 3,
      isRequired: required,
      maxParticipants: 120,
      startAt: DateTime(2027, 6, 30, 9, 30),
      location: location,
      approvalStatus: status,
      isHidden: hidden,
    );

final _activities = [
  _activity(
    1,
    name: 'ค่ายทักษะการทำงานเป็นทีมและการสื่อสารอย่างสร้างสรรค์ ครั้งที่ 4/2570',
    required: true,
  ),
  _activity(2, status: 'pending', location: 'ศูนย์ประชุมนานาชาติ อาคารเฉลิมพระเกียรติ ชั้น 3'),
  _activity(3, status: 'pending', hidden: true),
];

/// หน้าเต็มแบบที่ผู้ใช้เห็นจริง: เปลือกผู้ดูแล (แถบเมนู + ขอบหน้า) + การ์ดตาราง
/// — ความกว้างที่ตารางได้จึงเท่ากับบนจอจริง ไม่ใช่เท่ากว้างหน้าต่างทั้งหมด
Future<void> _pumpPage(
  WidgetTester tester,
  double width, {
  String role = 'admin',
  List<Activity>? activities,
  List<CriteriaSet> criteriaSets = const [],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  authService.token = 'fake-token';
  authService.username = role;
  authService.role = role;

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: AdminPage(
      activeId: 'activities',
      title: 'จัดการกิจกรรม',
      child: TableCard(
        child: ActivitiesTable(
          activities: activities ?? _activities,
          criteriaSets: criteriaSets,
          isStudent: role == 'student',
          canWrite: role != 'student',
          isAdmin: role == 'admin',
          onAction: (_, _) {},
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  tearDown(() => authService.logout());

  group('คอลัมน์ตารางกิจกรรม', () {
    test('staff/admin: ชื่อ · วันเวลา · สถานที่ · ประเภท · หมวด · ชั่วโมง · สถานะ · จัดการ', () {
      expect(activityTableColumns(false).map(_labelOf).toList(), _allLabels);
    });

    test('มุมมองนิสิตตัดแค่ "สถานะอนุมัติ"', () {
      expect(
        activityTableColumns(true).map(_labelOf).toList(),
        [..._allLabels]..remove('สถานะอนุมัติ'),
      );
    });

    test('"บังคับ" และ "รับสูงสุด" ไม่มีคอลัมน์แยกแล้ว (ย้ายไปอยู่บนชื่อ)', () {
      final labels = activityTableColumns(false).map(_labelOf);
      expect(labels, isNot(contains('บังคับ')));
      expect(labels, isNot(contains('รับสูงสุด')));
    });

    test('คอลัมน์ข้อความแชร์ความกว้างแบบ flex · ที่เหลือกว้างคงที่', () {
      final columns = {for (final c in activityTableColumns(false)) _labelOf(c): c};
      for (final label in ['ชื่อกิจกรรม', 'สถานที่', 'ประเภท', 'นับเข้าหมวด']) {
        expect(columns[label]!.columnWidth, isA<FlexColumnWidth>(), reason: label);
      }
      for (final label in ['วันเวลา', 'ชั่วโมงที่ได้', 'สถานะอนุมัติ', 'จัดการ']) {
        expect(columns[label]!.columnWidth, isA<FixedColumnWidth>(), reason: label);
      }
      expect(columns['ชั่วโมงที่ได้']!.numeric, isTrue);
    });

    test('ความกว้างคงที่รวม padding ของเซลล์ — เนื้อหาไม่ถูกบีบเหลือน้อยกว่าที่ตั้ง', () {
      final columns = activityTableColumns(false);
      final date = columns[1].columnWidth! as FixedColumnWidth;
      expect(date.value, kThaiDateCellWidth + kActivityColumnSpacing);

      for (final compact in [false, true]) {
        final actions = activityTableColumns(false, compact: compact).last.columnWidth!
            as FixedColumnWidth;
        expect(
          actions.value,
          ActivityActionButtons.widthFor(compact: compact) +
              kActivityColumnSpacing / 2 +
              kActivityTableMargin,
        );
      }
    });

    test('เซลล์ต่อแถวเท่าจำนวนคอลัมน์ ทั้งมุมมอง staff และนิสิต', () {
      for (final isStudent in [false, true]) {
        expect(
          activityTableCells(_activities.first, isStudent: isStudent, actions: const SizedBox())
              .length,
          activityTableColumns(isStudent).length,
        );
      }
    });
  });

  group('ทุกคอลัมน์พอดีจอ ไม่ต้องเลื่อนแนวนอน', () {
    for (final width in [1280.0, 1440.0]) {
      testWidgets('กว้าง ${width.toInt()}: ไม่มีแถบเลื่อนแนวนอน และทุกคอลัมน์อยู่ในจอครบ',
          (tester) async {
        await _pumpPage(tester, width);

        expect(tester.takeException(), isNull, reason: 'ต้องไม่ overflow');

        final inCard = find.byType(TableCard);
        expect(
          find.descendant(
            of: inCard,
            matching: find.byWidgetPredicate((w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.left ||
                    w.axisDirection == AxisDirection.right)),
          ),
          findsNothing,
          reason: 'ตารางต้องไม่มีส่วนที่เลื่อนแนวนอน',
        );
        expect(find.descendant(of: inCard, matching: find.byType(Scrollbar)), findsNothing);

        final table = tester.getRect(find.byType(DataTable));
        expect(table.right, lessThanOrEqualTo(width + 0.5), reason: 'ตารางเกินขอบจอ');

        for (final label in _allLabels) {
          // หาเฉพาะในตาราง — แถบเมนูข้างก็มีคำว่า "หมวดชั่วโมง" เหมือนกัน
          final header = tester.getRect(
            find.descendant(of: find.byType(DataTable), matching: find.text(label)),
          );
          expect(header.left, greaterThanOrEqualTo(table.left - 0.5), reason: '"$label" หลุดซ้าย');
          expect(header.right, lessThanOrEqualTo(table.right + 0.5), reason: '"$label" หลุดขวา');
        }

        // ปุ่มจัดการทุกแถว (ครบหรือโหมดย่อ) ต้องอยู่ในตาราง ไม่ล้นขอบ
        final buttons = find.descendant(
          of: find.byType(ActivitiesTable),
          matching: find.byWidgetPredicate(
              (w) => w is AppIconButton || w is PopupMenuButton<ActivityAction>),
        );
        expect(buttons, findsWidgets);
        for (final element in buttons.evaluate()) {
          final box = element.renderObject! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          expect(rect.right, lessThanOrEqualTo(table.right + 0.5));
          expect(rect.left, greaterThanOrEqualTo(table.left - 0.5));
        }
        expect(find.byType(ActivityActionButtons), findsNWidgets(_activities.length));
        expect(find.byType(ActivityApprovalChips), findsNWidgets(_activities.length));
      });
    }

    testWidgets('ตารางกว้างเท่าการ์ดพอดี — ไม่กว้างเกินจนต้องเลื่อน ไม่แคบกว่าจนเหลือที่ว่าง',
        (tester) async {
      await _pumpPage(tester, 1280);

      final card = tester.getRect(find.descendant(
        of: find.byType(TableCard),
        matching: find.byType(AppCard),
      ));
      final table = tester.getRect(find.byType(DataTable));
      expect(table.width, moreOrLessEquals(card.width, epsilon: 2));
    });

    testWidgets('นิสิต: ไม่มีคอลัมน์สถานะ ไม่มีปุ่มจัดการ และยังพอดีจอ', (tester) async {
      await _pumpPage(tester, 1280, role: 'student');

      expect(tester.takeException(), isNull);
      expect(find.text('สถานะอนุมัติ'), findsNothing);
      expect(find.byType(ActivityActionButtons), findsNothing);
      expect(tester.getRect(find.byType(DataTable)).right, lessThanOrEqualTo(1280.5));
    });
  });

  group('"ชั่วโมงที่ได้" กับ "นับเข้าหมวด" ต้องไม่สับสนกัน', () {
    test('หัวคอลัมน์สองอันต่างกันชัด — ไม่มีคำหนึ่งซ้อนอยู่ในอีกคำ', () {
      final labels = activityTableColumns(false).map(_labelOf).toList();
      expect(labels, containsAll(['ชั่วโมงที่ได้', 'นับเข้าหมวด']));
      expect(labels, isNot(contains('ชั่วโมง')), reason: 'หัวเดิมที่ชื่อชนกัน');
      expect(labels, isNot(contains('หมวดชั่วโมง')), reason: 'หัวเดิมที่ชื่อชนกัน');
      expect('นับเข้าหมวด', isNot(contains('ชั่วโมง')));
      expect('ชั่วโมงที่ได้', isNot(contains('หมวด')));
    });

    test('ชั่วโมงแสดงพร้อมหน่วย "N ชม." ไม่ใช่เลขลอย ๆ', () {
      expect(activityHoursLabel(_activity(1)), '3 ชม.');
      final half = Activity(
        name: 'x',
        activityType: 'วิชาการ',
        hours: 4.5,
        maxParticipants: 10,
        startAt: DateTime(2027, 1, 1),
        location: 'y',
      );
      expect(activityHoursLabel(half), '4.5 ชม.');
    });

    testWidgets('เซลล์ชั่วโมงในตารางขึ้น "N ชม." และชิดขวาตรงกับหัวคอลัมน์', (tester) async {
      await _pumpPage(tester, 1440);

      final inTable = find.byType(DataTable);
      final cells = find.descendant(of: inTable, matching: find.text('3 ชม.'));
      expect(cells, findsNWidgets(_activities.length));
      expect(
        find.descendant(of: inTable, matching: find.text('3')),
        findsNothing,
        reason: 'ต้องไม่มีเลขลอย ๆ ไร้หน่วย',
      );

      final headerRight = tester
          .getRect(find.descendant(of: inTable, matching: find.text('ชั่วโมงที่ได้')))
          .right;
      for (var i = 0; i < _activities.length; i++) {
        expect(tester.getRect(cells.at(i)).right, moreOrLessEquals(headerRight, epsilon: 1),
            reason: 'แถว $i: ตัวเลขต้องชิดขวาตรงหัวคอลัมน์');
      }
    });

    testWidgets('"นับเข้าหมวด" ข้อความยาวตัด … และ tooltip บอกชื่อรายการเกณฑ์เต็ม', (tester) async {
      const longCriteria = 'ด้านการสร้างนวัตกรรมสังคมและการเป็นผู้ประกอบการเพื่อชุมชนท้องถิ่น';
      final criteriaSets = [
        const CriteriaSet(
          id: 1,
          code: '2567-regular',
          name: 'เกณฑ์ 2567',
          groups: [
            CriteriaGroup(
              key: 'talent:1',
              name: 'TSU Social Talent',
              requirements: [CriteriaRequirement(id: 7, name: longCriteria)],
            ),
          ],
        ),
      ];
      final activity = Activity(
        id: 1,
        name: 'กิจกรรมทดสอบ',
        activityType: 'วิชาการ',
        hours: 3,
        maxParticipants: 50,
        startAt: DateTime(2027, 2, 1, 9),
        location: 'หอประชุม',
        approvalStatus: 'approved',
        requirementIds: const [7],
      );
      await _pumpPage(tester, 1280, activities: [activity], criteriaSets: criteriaSets);

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text(longCriteria));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.text(longCriteria), matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, longCriteria);

      // ไม่ล้นเข้าคอลัมน์ "ชั่วโมงที่ได้" ที่อยู่ถัดไป
      final hoursHeaderLeft = tester
          .getRect(find.descendant(of: find.byType(DataTable), matching: find.text('ชั่วโมงที่ได้')))
          .left;
      expect(
        tester
            .getRect(find.ancestor(of: find.text(longCriteria), matching: find.byType(TruncatedCell)))
            .right,
        lessThanOrEqualTo(hoursHeaderLeft),
      );
    });
  });

  group('ชื่อกิจกรรมรวม "บังคับ" และ "รับสูงสุด" ไว้แทนคอลัมน์แยก', () {
    test('tooltip ของชื่อบอกชื่อเต็ม รับสูงสุด และบังคับ/ไม่บังคับ', () {
      final required = activityNameTooltip(_activity(1, name: 'ปฐมนิเทศ', required: true));
      expect(required, 'ปฐมนิเทศ\nรับสูงสุด 120 คน · กิจกรรมบังคับ');
      expect(activityNameTooltip(_activity(2, name: 'ค่าย')), contains('ไม่บังคับ'));
    });

    testWidgets('ป้าย "บังคับ" ขึ้นเฉพาะกิจกรรมบังคับ และชื่อยาวถูกตัด …', (tester) async {
      await _pumpPage(tester, 1280);

      final names = find.byType(ActivityNameCell);
      expect(
        find.descendant(of: names.at(0), matching: find.widgetWithText(StatusChip, 'บังคับ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: names.at(1), matching: find.widgetWithText(StatusChip, 'บังคับ')),
        findsNothing,
      );

      final name = tester.widget<Text>(find.text(_activities.first.name));
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.text(_activities.first.name), matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, activityNameTooltip(_activities.first));
    });
  });

  group('ข้อความยาวถูกตัดและบอกเต็มตอนชี้', () {
    testWidgets('TruncatedCell ตัดบรรทัดเดียวและมี tooltip ข้อความเต็ม', (tester) async {
      const full = 'ด้านการสร้างนวัตกรรมสังคม (หน่วยใฝ่เรียนรู้ตลอดชีวิต)';
      await tester.pumpWidget(_wrap(const TruncatedCell(full, maxWidth: 80)));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text(full));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, full);
      expect(tester.getSize(find.byType(TruncatedCell)).width, lessThanOrEqualTo(80));
    });
  });

  group('วันเวลาเป็นเวลาไทย พ.ศ.', () {
    test('ตารางแสดงวันที่แบบ พ.ศ. ไม่ใช่ ISO', () {
      expect(formatThaiDate(DateTime(2027, 2, 1, 9, 30)), '1 ก.พ. 2570');
      expect(formatThaiDate(DateTime(2027, 2, 1)), isNot(contains('2027')));
    });

    test('tooltip/การ์ดบอกเวลาเต็มเป็น พ.ศ. เหมือนกัน', () {
      expect(formatThaiDateTime(DateTime(2027, 2, 1, 9, 30)), '1 ก.พ. 2570 เวลา 09:30 น.');
    });

    testWidgets('เซลล์วันที่กว้างคงที่ บรรทัดเดียว และแสดงปี พ.ศ. ครบ 4 หลัก', (tester) async {
      const longest = '28 เม.ย. 2570';
      const shortest = '1 ก.พ. 2570';
      await tester.pumpWidget(_wrap(const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThaiDateCell(longest, key: ValueKey('long')),
          ThaiDateCell(shortest, key: ValueKey('short'), tooltip: '1 ก.พ. 2570 เวลา 09:30 น.'),
        ],
      )));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(const ValueKey('long'))).width, kThaiDateCellWidth);
      expect(tester.getSize(find.byKey(const ValueKey('short'))).width, kThaiDateCellWidth);
      for (final text in [longest, shortest]) {
        final widget = tester.widget<Text>(find.text(text));
        expect(widget.maxLines, 1);
        expect(widget.softWrap, isFalse);
        expect(widget.overflow, isNot(TextOverflow.ellipsis), reason: 'ต้องเห็นปีครบ ไม่ใช่ …');
      }
      expect(find.byTooltip('1 ก.พ. 2570 เวลา 09:30 น.'), findsOneWidget);
    });

    test('เซลล์วันที่กว้างกว่าวันที่ยาวสุดที่วัดด้วย Sarabun จริง พร้อมเผื่อ', () {
      expect(kThaiDateCellWidth, greaterThanOrEqualTo(kThaiDateWidestMeasured + 12));
    });

    testWidgets('เซลล์วันที่ในตารางขึ้นเป็น พ.ศ.', (tester) async {
      await _pumpPage(tester, 1440);

      expect(find.text('30 มิ.ย. 2570'), findsNWidgets(_activities.length));
      expect(find.textContaining('2027-06-30'), findsNothing);
    });
  });

  group('ชิปสถานะอนุมัติ', () {
    testWidgets('อนุมัติแล้ว = เขียว · รออนุมัติ = เหลือง', (tester) async {
      await tester.pumpWidget(_wrap(Column(
        children: [
          StatusChip.activityApproval('approved'),
          StatusChip.activityApproval('pending'),
        ],
      )));
      await tester.pumpAndSettle();

      final approved = tester.widget<StatusChip>(find.widgetWithText(StatusChip, 'อนุมัติแล้ว'));
      final pending = tester.widget<StatusChip>(find.widgetWithText(StatusChip, 'รออนุมัติ'));
      expect(approved.palette, StatusPalette.approved);
      expect(pending.palette, StatusPalette.pending,
          reason: 'เทาอ่านเหมือนไม่มีอะไรต้องทำ ทั้งที่เป็นคิวรออนุมัติ');
      expect(pending.palette, isNot(StatusPalette.neutral));
    });

    testWidgets('ซ่อนอยู่เป็นไอคอนพร้อม tooltip ไม่ใช่ชิปที่สอง (คอลัมน์สถานะจึงแคบได้)',
        (tester) async {
      await tester.pumpWidget(_wrap(ActivityApprovalChips(activity: _activity(1, hidden: true))));
      await tester.pumpAndSettle();

      expect(find.byType(StatusChip), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byTooltip('ซ่อนอยู่ — นิสิตไม่เห็นกิจกรรมนี้'), findsOneWidget);
    });
  });

  group('สิทธิ์กดอนุมัติกิจกรรม', () {
    test('admin อนุมัติกิจกรรมที่ยังรออยู่ได้', () {
      expect(canApproveActivity('pending', isAdmin: true), isTrue);
    });

    test('กิจกรรมที่อนุมัติไปแล้วไม่มีปุ่มให้กดซ้ำ', () {
      expect(canApproveActivity('approved', isAdmin: true), isFalse);
    });

    test('staff เห็นสถานะได้ แต่กดอนุมัติเองไม่ได้', () {
      // backend ตอบ 403 ให้ staff อยู่แล้ว (test_staff_cannot_approve_activity)
      expect(canApproveActivity('pending', isAdmin: false), isFalse);
      expect(canApproveActivity('approved', isAdmin: false), isFalse);
    });

    test('ผูกกับบทบาทจริงใน authService ไม่ใช่ค่าที่ส่งมาลอย ๆ', () {
      authService.role = 'staff';
      expect(canApproveActivity('pending', isAdmin: authService.isAdmin), isFalse);

      authService.role = 'admin';
      expect(canApproveActivity('pending', isAdmin: authService.isAdmin), isTrue);
    });
  });
}
