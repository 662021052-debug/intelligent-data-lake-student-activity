import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/pagination_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ต้องใช้ธีมของแอป (splash เป็น InkRipple) ไม่งั้นการแตะปุ่มจะไปเรียก shader
// ink_sparkle.frag ที่ test ไม่มี asset ให้
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('PaginationBar', () {
    testWidgets('หน้าแรก: ปิดปุ่มย้อนกลับ เปิดปุ่มถัดไป', (tester) async {
      await tester.pumpWidget(_wrap(PaginationBar(
        skip: 0,
        limit: 50,
        total: 104,
        onChanged: (_) {},
      )));

      expect(find.text('1-50 จาก 104'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left)).onPressed,
          isNull);
      expect(
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
          isNotNull);
    });

    testWidgets('กดถัดไปส่ง skip ของหน้าถัดไปกลับมา', (tester) async {
      int? changedTo;
      await tester.pumpWidget(_wrap(PaginationBar(
        skip: 0,
        limit: 50,
        total: 104,
        onChanged: (skip) => changedTo = skip,
      )));

      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(changedTo, 50);
    });

    testWidgets('หน้าสุดท้ายนับรายการที่เหลือถูกและปิดปุ่มถัดไป', (tester) async {
      await tester.pumpWidget(_wrap(PaginationBar(
        skip: 100,
        limit: 50,
        total: 104,
        onChanged: (_) {},
      )));

      expect(find.text('101-104 จาก 104'), findsOneWidget);
      expect(
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
          isNull);
    });

    testWidgets('ไม่มีข้อมูลเลย แสดง 0-0 จาก 0 และปิดทั้งสองปุ่ม', (tester) async {
      await tester.pumpWidget(_wrap(PaginationBar(
        skip: 0,
        limit: 50,
        total: 0,
        onChanged: (_) {},
      )));

      expect(find.text('0-0 จาก 0'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left)).onPressed,
          isNull);
      expect(
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed,
          isNull);
    });
  });
}
