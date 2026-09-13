import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/format.dart';
import 'package:activity_tracking_frontend/widgets/app_sticky_table.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _labelOf(DataColumn column) => ((column.label as Text).data)!;

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

/// ตารางย่อที่มีโครงเหมือนหน้าจัดการกิจกรรม — หน้าจริงยิง API ตอนเปิดซึ่งล้มในเทสต์
Widget _table({required double width, bool isStudent = false}) {
  return SizedBox(
    width: width,
    child: AppStickyTable(
      scrollableColumns: activityScrollColumns(),
      pinnedColumns: activityPinnedColumns(isStudent),
      rows: [
        for (var i = 0; i < 3; i++)
          StickyRow(
            scrollable: [
              const DataCell(TruncatedCell(
                'กิจกรรมชื่อยาวมากจนดันคอลัมน์อื่นหลุดจอถ้าไม่ตัดข้อความ',
                maxWidth: 220,
              )),
              const DataCell(TruncatedCell('อบรม/สัมมนา', maxWidth: 110)),
              const DataCell(TruncatedCell(
                'ด้านการสร้างนวัตกรรมสังคม (หน่วยใฝ่เรียนรู้ตลอดชีวิต)',
                maxWidth: 170,
              )),
              const DataCell(NarrowCell(Text('6'), width: 36)),
              const DataCell(NarrowCell(Icon(Icons.remove, size: 18), width: 32)),
              const DataCell(NarrowCell(Text('120'), width: 40)),
              DataCell(Text(formatThaiDate(DateTime(2027, 2, 1, 9, 30)))),
              const DataCell(TruncatedCell('หอประชุมใหญ่', maxWidth: 140)),
            ],
            pinned: [
              if (!isStudent)
                const DataCell(StatusChip(
                  label: 'รออนุมัติ',
                  palette: StatusPalette.pending,
                  dense: true,
                )),
              DataCell(IconButton(icon: const Icon(Icons.edit), onPressed: () {})),
            ],
          ),
      ],
    ),
  );
}

void main() {
  group('คอลัมน์ตารางกิจกรรม', () {
    test('ฝั่งตรึงมี "สถานะอนุมัติ" + "จัดการ" สำหรับ staff/admin', () {
      final pinned = activityPinnedColumns(false).map(_labelOf).toList();
      expect(pinned, ['สถานะอนุมัติ', 'จัดการ']);
    });

    test('มุมมองนิสิตตรึงแค่คอลัมน์จัดการ ไม่มีสถานะอนุมัติ', () {
      final pinned = activityPinnedColumns(true).map(_labelOf).toList();
      expect(pinned, ['จัดการ']);
    });

    test('คอลัมน์ที่เลื่อนได้ไม่มีสถานะ/จัดการปนอยู่ (ไม่งั้นจะซ้ำสองที่)', () {
      final scrollable = activityScrollColumns().map(_labelOf).toList();
      expect(scrollable, isNot(contains('สถานะอนุมัติ')));
      expect(scrollable, isNot(contains('จัดการ')));
      expect(scrollable.first, 'ชื่อกิจกรรม');
    });

    test('ชั่วโมง/รับสูงสุด เป็นคอลัมน์ตัวเลข (ชิดขวา กินความกว้างน้อยกว่า)', () {
      final columns = {
        for (final c in activityScrollColumns()) _labelOf(c): c.numeric,
      };
      expect(columns['ชั่วโมง'], isTrue);
      expect(columns['รับสูงสุด'], isTrue);
      expect(columns['ชื่อกิจกรรม'], isFalse);
    });
  });

  group('คอลัมน์สถานะ + จัดการ ต้องเห็นทุกขนาดจอ', () {
    for (final width in [760.0, 1024.0, 1280.0, 1600.0]) {
      testWidgets('ที่ความกว้าง ${width.toInt()} ยังเห็นทั้งสองคอลัมน์', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_wrap(_table(width: width)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'ต้องไม่ overflow');
        expect(find.text('สถานะอนุมัติ'), findsOneWidget);
        expect(find.text('จัดการ'), findsOneWidget);

        // เห็นจริง ไม่ใช่แค่มีอยู่ในต้นไม้ — ต้องอยู่ในกรอบจอ
        final actions = tester.getRect(find.text('จัดการ'));
        expect(actions.right, lessThanOrEqualTo(width + 0.5),
            reason: 'คอลัมน์จัดการหลุดขอบขวาที่ความกว้าง $width');
        expect(actions.left, greaterThanOrEqualTo(0));
      });
    }

    testWidgets('ฝั่งตรึงไม่เลื่อนตามเมื่อเลื่อนตารางไปทางขวา', (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(_table(width: 900)));
      await tester.pumpAndSettle();

      final before = tester.getRect(find.text('จัดการ'));
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(-300, 0));
      await tester.pumpAndSettle();
      final after = tester.getRect(find.text('จัดการ'));

      expect(after, before, reason: 'คอลัมน์ที่ตรึงไว้ต้องอยู่ที่เดิม');
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

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, full);

      // กว้างไม่เกินที่กำหนด ไม่ว่าข้อความจะยาวแค่ไหน
      expect(tester.getSize(find.byType(TruncatedCell)).width, lessThanOrEqualTo(80));
    });
  });

  group('วันเวลาเป็นเวลาไทย พ.ศ.', () {
    test('ตารางแสดงวันที่แบบ พ.ศ. ไม่ใช่ ISO', () {
      expect(formatThaiDate(DateTime(2027, 2, 1, 9, 30)), '1 ก.พ. 2570');
      expect(formatThaiDate(DateTime(2027, 2, 1)), isNot(contains('2027')));
    });

    test('tooltip/การ์ดบอกเวลาเต็มเป็น พ.ศ. เหมือนกัน', () {
      expect(
        formatThaiDateTime(DateTime(2027, 2, 1, 9, 30)),
        '1 ก.พ. 2570 เวลา 09:30 น.',
      );
    });

    testWidgets('เซลล์วันที่กว้างคงที่ บรรทัดเดียว และแสดงปี พ.ศ. ครบ 4 หลัก', (tester) async {
      // วันที่ยาวสุดที่เกิดได้ (วัน 2 หลัก + เดือนตัวย่อยาวสุด) และสั้นสุด
      const longest = '30 มิ.ย. 2570';
      const shortest = '1 ก.พ. 2570';
      await tester.pumpWidget(_wrap(const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThaiDateCell(longest, key: ValueKey('long')),
          ThaiDateCell(shortest, key: ValueKey('short'), tooltip: '1 ก.พ. 2570 เวลา 09:30 น.'),
        ],
      )));
      await tester.pumpAndSettle();

      // ความกว้างไม่ขึ้นกับความยาวข้อความ (หรือฟอนต์ที่ใช้วัดตอนนั้น) — คอลัมน์จึงไม่หดจนตัดปี
      expect(tester.getSize(find.byKey(const ValueKey('long'))).width, kThaiDateCellWidth);
      expect(tester.getSize(find.byKey(const ValueKey('short'))).width, kThaiDateCellWidth);

      for (final text in [longest, shortest]) {
        final widget = tester.widget<Text>(find.text(text));
        expect(widget.maxLines, 1);
        expect(widget.softWrap, isFalse, reason: 'ห้ามตัดปีลงบรรทัดใหม่แล้วโดนความสูงแถวบัง');
        expect(widget.overflow, isNot(TextOverflow.ellipsis), reason: 'ต้องเห็นปีครบ ไม่ใช่ …');
        expect(text, endsWith('2570'));
      }
      expect(find.byTooltip('1 ก.พ. 2570 เวลา 09:30 น.'), findsOneWidget);
    });

    test('ความกว้างเซลล์วันที่เผื่อพอสำหรับวันที่ยาวสุดด้วยฟอนต์จริง', () {
      // "30 มิ.ย. 2570" = 13 ตัวอักษร · Sarabun 14px เฉลี่ยราว 7px/ตัว ≈ 91px
      expect(kThaiDateCellWidth, greaterThanOrEqualTo(13 * 7 + 16));
    });

    testWidgets('เซลล์วันเวลาในตารางขึ้นเป็น พ.ศ.', (tester) async {
      await tester.pumpWidget(_wrap(_table(width: 1280)));
      await tester.pumpAndSettle();

      expect(find.text('1 ก.พ. 2570'), findsWidgets);
      expect(find.textContaining('2027-02-01'), findsNothing);
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

      final approved = tester.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'อนุมัติแล้ว'),
      );
      final pending = tester.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'รออนุมัติ'),
      );

      expect(approved.palette, StatusPalette.approved);
      expect(pending.palette, StatusPalette.pending,
          reason: 'เทาอ่านเหมือนไม่มีอะไรต้องทำ ทั้งที่เป็นคิวรออนุมัติ');
      expect(pending.palette, isNot(StatusPalette.neutral));
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
      // ฝั่ง UI จึงต้องไม่โชว์ปุ่มที่กดแล้วเด้ง error แน่ ๆ
      expect(canApproveActivity('pending', isAdmin: false), isFalse);
      expect(canApproveActivity('approved', isAdmin: false), isFalse);
    });

    test('ผูกกับบทบาทจริงใน authService ไม่ใช่ค่าที่ส่งมาลอย ๆ', () {
      authService.role = 'staff';
      expect(canApproveActivity('pending', isAdmin: authService.isAdmin), isFalse);

      authService.role = 'admin';
      expect(canApproveActivity('pending', isAdmin: authService.isAdmin), isTrue);

      authService.logout();
    });
  });
}
