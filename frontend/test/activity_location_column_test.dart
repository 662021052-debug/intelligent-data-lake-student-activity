import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_table_cells.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _labelOf(DataColumn column) => (column.label as ActivityColumnLabel).text;

const _longLocation = 'ศูนย์ประชุมนานาชาติ อาคารเฉลิมพระเกียรติ ชั้น 3 ห้องประชุมใหญ่';

Activity _activity(int i, String location) => Activity(
      id: i,
      name: 'กิจกรรมที่ $i',
      activityType: 'วิชาการ',
      maxParticipants: 100,
      startAt: DateTime(2027, 2, 1, 9, 30),
      location: location,
      approvalStatus: 'approved',
    );

final _activities = [
  _activity(1, 'ห้อง SC101'),
  _activity(2, _longLocation),
  _activity(3, 'ลานกิจกรรม'),
];

/// ตารางจริง (ActivitiesTable) ที่ความกว้างตารางที่กำหนด
Future<void> _pumpAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: ActivitiesTable(
          activities: _activities,
          isStudent: false,
          canWrite: true,
          isAdmin: true,
          onAction: (_, _) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _locationCell(String location) =>
    find.ancestor(of: find.text(location), matching: find.byType(TruncatedCell));

void main() {
  group('คอลัมน์สถานที่', () {
    test('มีคอลัมน์ "สถานที่" ถัดจากวันเวลา และมีคอลัมน์เดียว', () {
      final labels = activityTableColumns(false).map(_labelOf).toList();
      expect(labels.indexOf('สถานที่'), labels.indexOf('วันเวลา') + 1);
      expect(labels.where((l) => l == 'สถานที่'), hasLength(1));
    });

    test('เซลล์ที่ตำแหน่งสถานที่คือ location และความกว้างมาจากตาราง (flex)', () {
      final a = _activity(9, 'หอประชุมใหญ่');
      final labels = activityTableColumns(false).map(_labelOf).toList();
      final cell = activityTableCells(a, isStudent: false, actions: const SizedBox())[
          labels.indexOf('สถานที่')]
          .child as TruncatedCell;
      expect(cell.text, 'หอประชุมใหญ่');
      expect(cell.maxWidth, double.infinity, reason: 'คอลัมน์ flex — ตารางเป็นคนกำหนดขอบ');
    });

    testWidgets('แสดง location ของแต่ละแถวถูกต้อง', (tester) async {
      await _pumpAt(tester, 1280);

      for (final a in _activities) {
        expect(_locationCell(a.location), findsOneWidget, reason: 'แถว ${a.id}');
      }
    });

    testWidgets('ชื่อสถานที่ยาวถูกตัดบรรทัดเดียว (…) ภายในคอลัมน์ และ tooltip บอกชื่อเต็ม',
        (tester) async {
      await _pumpAt(tester, 1280);

      final text = tester.widget<Text>(find.text(_longLocation));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);

      // ไม่ล้นเข้าคอลัมน์ถัดไป ("ประเภท")
      final typeHeader = tester.getRect(find.text('ประเภท'));
      expect(tester.getRect(_locationCell(_longLocation)).right,
          lessThanOrEqualTo(typeHeader.left));

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: find.text(_longLocation), matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, _longLocation);

      // ชี้ค้างแล้ว tooltip ขึ้นชื่อเต็มจริง
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text(_longLocation)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(_longLocation), findsNWidgets(2), reason: 'ตัวในเซลล์ + ตัวใน tooltip');
    });

    for (final width in [1024.0, 1280.0, 1440.0]) {
      testWidgets('กว้าง ${width.toInt()}: คอลัมน์สถานะ/จัดการ ยังอยู่ในตารางครบ', (tester) async {
        await _pumpAt(tester, width);

        expect(tester.takeException(), isNull, reason: 'ต้องไม่ overflow');
        for (final label in ['สถานที่', 'สถานะอนุมัติ', 'จัดการ']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width + 0.5), reason: '"$label" หลุดขอบขวา');
        }
        expect(find.byType(ActivityApprovalChips), findsNWidgets(_activities.length));
        expect(find.byType(ActivityActionButtons), findsNWidgets(_activities.length));
      });
    }

    test('การ์ดจอแคบแสดงสถานที่', () {
      final subtitle = activityCardSubtitle(_activity(1, 'ห้อง SC101'));
      expect(subtitle, contains('สถานที่: ห้อง SC101'));
      expect(subtitle, contains('1 ก.พ. 2570'), reason: 'บรรทัดแรกยังบอกวันเวลาเหมือนเดิม');
    });
  });
}
