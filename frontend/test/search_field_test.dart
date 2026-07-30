import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _debounce = Duration(milliseconds: 350);

Future<List<String>> _pumpField(WidgetTester tester) async {
  final searches = <String>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: DebouncedSearchField(
        label: 'ค้นหา',
        onSearch: searches.add,
      ),
    ),
  ));
  return searches;
}

void main() {
  group('DebouncedSearchField', () {
    testWidgets('พิมพ์แล้วค้นหาเอง ไม่ต้องกด Enter', (tester) async {
      final searches = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), 'สมชาย');
      await tester.pump(const Duration(milliseconds: 100));
      expect(searches, isEmpty, reason: 'ยังไม่ครบเวลาหน่วง ต้องยังไม่ยิง');

      await tester.pump(_debounce);
      expect(searches, ['สมชาย']);
    });

    testWidgets('พิมพ์รัว ๆ ยิงครั้งเดียวด้วยคำล่าสุด', (tester) async {
      final searches = await _pumpField(tester);

      for (final text in ['ส', 'สม', 'สมช']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(searches, isEmpty);

      await tester.pump(_debounce);
      expect(searches, ['สมช'], reason: 'ไม่ยิง API ทุกตัวอักษร');
    });

    testWidgets('กด Enter ค้นทันทีไม่ต้องรอหน่วง', (tester) async {
      final searches = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), 'กีฬา');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(searches, ['กีฬา']);

      // debounce ที่ค้างอยู่ต้องถูกยกเลิก ไม่ยิงซ้ำด้วยคำเดิม
      await tester.pump(_debounce);
      expect(searches, ['กีฬา']);
    });

    testWidgets('ค่าที่ส่งออกไปถูก trim และไม่ยิงซ้ำถ้าคำค้นหาไม่เปลี่ยน', (tester) async {
      final searches = await _pumpField(tester);

      await tester.enterText(find.byType(TextField), '  กีฬา  ');
      await tester.pump(_debounce);
      expect(searches, ['กีฬา']);

      await tester.enterText(find.byType(TextField), 'กีฬา ');
      await tester.pump(_debounce);
      expect(searches, ['กีฬา'], reason: 'คำค้นหาเท่าเดิมหลัง trim จึงไม่ต้องโหลดใหม่');
    });

    testWidgets('ปุ่มล้างคำค้นหาโผล่เมื่อมีข้อความ และล้างแล้วค้นใหม่ทันที', (tester) async {
      final searches = await _pumpField(tester);
      expect(find.byIcon(Icons.clear), findsNothing);

      await tester.enterText(find.byType(TextField), 'สมชาย');
      await tester.pump(_debounce);
      expect(find.byIcon(Icons.clear), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(searches, ['สมชาย', '']);
      expect(find.byIcon(Icons.clear), findsNothing);
    });
  });
}
