import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_data_table.dart';
import 'package:activity_tracking_frontend/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('AppDataTable', () {
    testWidgets('แถวสลับสี (zebra) — แถวคู่โปร่ง แถวคี่มีพื้นหลังอ่อน', (tester) async {
      await tester.pumpWidget(_wrap(AppDataTable(
        columns: const [DataColumn(label: Text('ชื่อ'))],
        rows: const [
          [DataCell(Text('แถว 1'))],
          [DataCell(Text('แถว 2'))],
          [DataCell(Text('แถว 3'))],
        ],
      )));

      final rows = tester.widget<DataTable>(find.byType(DataTable)).rows;
      expect(rows.length, 3);

      Color? colorOf(int index) => rows[index].color?.resolve(<WidgetState>{});
      expect(colorOf(0), isNull, reason: 'แถวคู่ใช้พื้นหลังปกติของตาราง');
      expect(colorOf(1), isNotNull, reason: 'แถวคี่ต้องมีพื้นหลังอ่อน');
      expect(colorOf(2), isNull);
    });

    testWidgets('เมาส์ชี้แถวไหนแถวนั้นเปลี่ยนสี', (tester) async {
      await tester.pumpWidget(_wrap(AppDataTable(
        columns: const [DataColumn(label: Text('ชื่อ'))],
        rows: const [
          [DataCell(Text('แถว 1'))],
        ],
      )));

      final row = tester.widget<DataTable>(find.byType(DataTable)).rows.first;
      expect(
        row.color?.resolve(<WidgetState>{WidgetState.hovered}),
        isNot(row.color?.resolve(<WidgetState>{})),
      );
    });

    testWidgets('หัวตารางเป็นตัวหนาจากธีมเดียวของแอป', (tester) async {
      await tester.pumpWidget(_wrap(AppDataTable(
        columns: const [DataColumn(label: Text('ชื่อ'))],
        rows: const [
          [DataCell(Text('แถว 1'))],
        ],
      )));

      final theme = AppTheme.light;
      expect(theme.dataTableTheme.headingTextStyle?.fontWeight, FontWeight.w700);
    });
  });

  group('EmptyState', () {
    testWidgets('แสดงไอคอน + ข้อความ แทนพื้นที่ว่าง', (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(
        icon: Icons.event_busy,
        title: 'ยังไม่มีกิจกรรม',
        message: 'กดปุ่ม + เพื่อเพิ่มกิจกรรมแรก',
      )));

      expect(find.byIcon(Icons.event_busy), findsOneWidget);
      expect(find.text('ยังไม่มีกิจกรรม'), findsOneWidget);
      expect(find.text('กดปุ่ม + เพื่อเพิ่มกิจกรรมแรก'), findsOneWidget);
    });

    testWidgets('กรณีค้นหาไม่เจอ ใช้ข้อความคนละแบบกับ "ยังไม่มีข้อมูล"', (tester) async {
      await tester.pumpWidget(_wrap(EmptyState.noResults()));

      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.text('ไม่พบรายการที่ค้นหา'), findsOneWidget);
    });

    testWidgets('ErrorState มีปุ่มลองใหม่ที่เรียก callback', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_wrap(ErrorState(
        message: 'Exception: เชื่อมต่อไม่ได้',
        onRetry: () => retried++,
      )));

      // ข้อความ error ตัดคำว่า "Exception: " ออกก่อนแสดงให้ผู้ใช้
      expect(find.text('เชื่อมต่อไม่ได้'), findsOneWidget);
      await tester.tap(find.text('ลองใหม่'));
      expect(retried, 1);
    });
  });
}
