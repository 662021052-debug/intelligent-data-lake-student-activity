import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_buttons.dart';
import 'package:activity_tracking_frontend/widgets/app_sticky_table.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _activity(
  String name, {
  String status = 'pending',
  bool hidden = false,
  int participants = 0,
}) =>
    Activity(
      id: name.hashCode,
      name: name,
      activityType: 'วิชาการ',
      maxParticipants: 50,
      startAt: DateTime(2027, 2, 1, 9),
      location: 'หอประชุม',
      approvalStatus: status,
      isHidden: hidden,
      participantCount: participants,
    );

/// ทุกสถานะที่ทำให้ชุดปุ่มต่างกัน — รวมแถวที่ปุ่มเยอะสุด (4) และแถวที่มีสองชิป
final _rows = [
  _activity('รออนุมัติ', status: 'pending'), // อนุมัติ · ผู้เข้าร่วม · แก้ · ลบ
  _activity('อนุมัติแล้ว', status: 'approved', participants: 3), // QR · ผู้เข้าร่วม · แก้ · ซ่อน
  _activity('ซ่อน+รอ', status: 'pending', hidden: true), // เลิกซ่อน · อนุมัติ · ผู้เข้าร่วม · แก้
  _activity('ซ่อน+อนุมัติ', status: 'approved', hidden: true), // เลิกซ่อน · ผู้เข้าร่วม · แก้
];

Widget _table({
  required double width,
  required bool compact,
  void Function(Activity, ActivityAction)? onAction,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: AppStickyTable(
          scrollableColumns: activityScrollColumns().take(2).toList(),
          pinnedColumns: activityPinnedColumns(false),
          rows: [
            for (final (i, a) in _rows.indexed)
              StickyRow(
                scrollable: [
                  DataCell(TruncatedCell(a.name, maxWidth: 220), ),
                  DataCell(Text(a.activityType, key: ValueKey('type-$i'))),
                ],
                pinned: [
                  DataCell(ActivityApprovalChips(key: ValueKey('chips-$i'), activity: a)),
                  DataCell(ActivityActionButtons(
                    key: ValueKey('actions-$i'),
                    activity: a,
                    isAdmin: true,
                    compact: compact,
                    onAction: (action) => onAction?.call(a, action),
                  )),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _pumpAt(WidgetTester tester, double width, {required bool compact,
    void Function(Activity, ActivityAction)? onAction}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_table(width: width, compact: compact, onAction: onAction));
  await tester.pumpAndSettle();
}

List<Rect> _buttonRects(WidgetTester tester, int row) {
  final inRow = find.byKey(ValueKey('actions-$row'));
  return [
    ...tester.getRectsOf(find.descendant(of: inRow, matching: find.byType(AppIconButton))),
    ...tester.getRectsOf(
        find.descendant(of: inRow, matching: find.byType(PopupMenuButton<ActivityAction>))),
  ];
}

extension on WidgetTester {
  /// กรอบของทุกตัวที่ finder เจอ — วัดจาก render box ตรง ๆ เพราะวิดเจ็ต const
  /// ที่หน้าตาเหมือนกัน (ชิป "ซ่อนอยู่" คนละแถว) ใช้ find.byWidget แยกกันไม่ได้
  List<Rect> getRectsOf(Finder finder) => [
        for (final e in finder.evaluate())
          (e.renderObject! as RenderBox).localToGlobal(Offset.zero) &
              (e.renderObject! as RenderBox).size,
      ];
}

/// เส้นกึ่งกลางแนวตั้งของแถว — วัดจากเซลล์ฝั่งที่เลื่อนได้ (อีกตาราง) เพื่อจับการเหลื่อม
double _rowCenter(WidgetTester tester, int row) =>
    tester.getRect(find.byKey(ValueKey('type-$row'))).center.dy;

/// ข้อตรวจร่วม: บรรทัดเดียว · ทุกแถวสูงเท่ากัน · กึ่งกลางตรงแถว · ไม่ล้นข้ามแถว
void _expectAlignedRows(WidgetTester tester) {
  final centers = [for (var i = 0; i < _rows.length; i++) _rowCenter(tester, i)];
  final pitches = [for (var i = 1; i < centers.length; i++) centers[i] - centers[i - 1]];
  for (final pitch in pitches) {
    expect(pitch, moreOrLessEquals(pitches.first, epsilon: 0.5), reason: 'ทุกแถวต้องสูงเท่ากัน');
  }
  final rowHeight = pitches.first;

  final widths = <double>{};
  for (var i = 0; i < _rows.length; i++) {
    final rects = _buttonRects(tester, i);
    expect(rects, isNotEmpty);
    for (final rect in rects) {
      expect(rect.top, moreOrLessEquals(rects.first.top, epsilon: 0.5),
          reason: 'แถว $i: ปุ่มต้องอยู่บรรทัดเดียว');
      expect(rect.center.dy, moreOrLessEquals(centers[i], epsilon: 1),
          reason: 'แถว $i: ปุ่มต้องอยู่กึ่งกลางแนวตั้งของแถว');
      expect(rect.top, greaterThan(centers[i] - rowHeight / 2),
          reason: 'แถว $i: ปุ่มล้นขึ้นไปแถวบน');
      expect(rect.bottom, lessThan(centers[i] + rowHeight / 2),
          reason: 'แถว $i: ปุ่มล้นลงไปทับแถวล่าง');
    }
    // ปุ่มในแถวเดียวกันไม่ทับกันเอง
    final sorted = [...rects]..sort((a, b) => a.left.compareTo(b.left));
    for (var j = 1; j < sorted.length; j++) {
      expect(sorted[j].left, greaterThanOrEqualTo(sorted[j - 1].right));
    }
    widths.add(tester.getSize(find.byKey(ValueKey('actions-$i'))).width);

    final chips = tester.getRectsOf(
        find.descendant(of: find.byKey(ValueKey('chips-$i')), matching: find.byType(StatusChip)));
    for (final chip in chips) {
      expect(chip.top, moreOrLessEquals(chips.first.top, epsilon: 0.5),
          reason: 'แถว $i: ชิปสถานะต้องอยู่บรรทัดเดียว');
    }
  }
  expect(widths, hasLength(1), reason: 'กลุ่มปุ่มกว้างเท่ากันทุกแถว คอลัมน์จึงไม่กระโดด');
}

void main() {
  group('ชุดปุ่มตามสถานะกิจกรรม', () {
    test('ไม่มีแถวไหนเกิน kActivityActionSlots ปุ่ม ทุกการผสมสถานะ', () {
      for (final status in ['pending', 'approved']) {
        for (final hidden in [false, true]) {
          for (final participants in [0, 5]) {
            for (final isAdmin in [false, true]) {
              final a = _activity('x', status: status, hidden: hidden, participants: participants);
              expect(activityActionsFor(a, isAdmin: isAdmin).length,
                  lessThanOrEqualTo(kActivityActionSlots),
                  reason: '$status hidden=$hidden participants=$participants admin=$isAdmin');
            }
          }
        }
      }
    });

    test('กิจกรรม pending ของ admin มีปุ่มอนุมัติเป็นปุ่มหลัก (ตัวแรก)', () {
      expect(activityActionsFor(_rows[0], isAdmin: true), [
        ActivityAction.approve,
        ActivityAction.participants,
        ActivityAction.edit,
        ActivityAction.delete,
      ]);
      expect(activityActionsFor(_rows[0], isAdmin: false), isNot(contains(ActivityAction.approve)));
    });

    test('ยุบเป็นเมนู ⋮ เมื่อตารางแคบกว่าเกณฑ์เท่านั้น', () {
      expect(activityActionsCompact(900), isTrue);
      expect(activityActionsCompact(kActivityActionsCompactBelow), isFalse);
      expect(activityActionsCompact(1280), isFalse);
    });
  });

  group('โหมดปกติ: ปุ่มทั้งหมดบรรทัดเดียว', () {
    for (final width in [1024.0, 1280.0, 1600.0]) {
      testWidgets('กว้าง ${width.toInt()}: บรรทัดเดียว · แถวสูงเท่ากัน · ไม่ล้นข้ามแถว',
          (tester) async {
        await _pumpAt(tester, width, compact: false);

        expect(tester.takeException(), isNull, reason: 'ต้องไม่ overflow');
        expect(find.byType(PopupMenuButton<ActivityAction>), findsNothing);
        expect([for (var i = 0; i < _rows.length; i++) _buttonRects(tester, i).length],
            [4, 4, 4, 3]);
        _expectAlignedRows(tester);
      });
    }

    testWidgets('ปุ่มอนุมัติของกิจกรรม pending อยู่ในคอลัมน์จัดการและกดได้', (tester) async {
      final pressed = <(String, ActivityAction)>[];
      await _pumpAt(tester, 1280, compact: false, onAction: (a, x) => pressed.add((a.name, x)));

      final approve = find.descendant(
        of: find.byKey(const ValueKey('actions-0')),
        matching: find.byTooltip('อนุมัติกิจกรรม'),
      );
      expect(approve, findsOneWidget);
      await tester.tap(approve);
      expect(pressed, [('รออนุมัติ', ActivityAction.approve)]);
    });
  });

  group('โหมดย่อ: ปุ่มหลัก + เมนู ⋮', () {
    testWidgets('ทุกแถวมีปุ่มหลัก 1 + ⋮ 1 · แถวสูงเท่ากัน · ไม่ล้นข้ามแถว', (tester) async {
      await _pumpAt(tester, 900, compact: true);

      expect(tester.takeException(), isNull);
      for (var i = 0; i < _rows.length; i++) {
        final inRow = find.byKey(ValueKey('actions-$i'));
        expect(find.descendant(of: inRow, matching: find.byType(AppIconButton)), findsOneWidget);
        expect(find.descendant(of: inRow, matching: find.byType(PopupMenuButton<ActivityAction>)),
            findsOneWidget);
      }
      _expectAlignedRows(tester);
    });

    testWidgets('ปุ่มที่ถูกยุบอยู่ในเมนูเดียวครบ และเลือกแล้วส่ง action ถูกตัว', (tester) async {
      final pressed = <ActivityAction>[];
      await _pumpAt(tester, 900, compact: true, onAction: (_, x) => pressed.add(x));

      // แถว pending: ปุ่มหลักคืออนุมัติ ที่เหลืออยู่ในเมนู
      final row = find.byKey(const ValueKey('actions-0'));
      expect(find.descendant(of: row, matching: find.byTooltip('อนุมัติกิจกรรม')), findsOneWidget);
      await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.more_vert)));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuItem<ActivityAction>), findsNWidgets(3));
      for (final label in ['ดูผู้เข้าร่วม', 'แก้ไข', 'ลบ']) {
        expect(find.widgetWithText(PopupMenuItem<ActivityAction>, label), findsOneWidget);
      }
      await tester.tap(find.widgetWithText(PopupMenuItem<ActivityAction>, 'แก้ไข'));
      await tester.pumpAndSettle();
      expect(pressed, [ActivityAction.edit]);
    });
  });
}
