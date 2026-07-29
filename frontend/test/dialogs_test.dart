import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_form_dialog.dart';
import 'package:activity_tracking_frontend/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirmDelete สรุปสิ่งที่จะถูกลบ + เตือนว่ากู้คืนไม่ได้', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await confirmDelete(context, 'ปฐมนิเทศนิสิตใหม่'),
              child: const Text('ลบ'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ลบ'));
    await tester.pumpAndSettle();

    expect(find.text('ยืนยันการลบ'), findsOneWidget);
    expect(find.text('ต้องการลบ "ปฐมนิเทศนิสิตใหม่" ใช่หรือไม่?'), findsOneWidget);
    expect(find.text('ลบแล้วไม่สามารถกู้คืนได้'), findsOneWidget);

    // ปุ่มยืนยันอยู่ขวาสุด (หลังปุ่มยกเลิก) และเป็นปุ่ม primary
    expect(find.widgetWithText(TextButton, 'ยกเลิก'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'ลบ'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('AppFormDialog: ปุ่มยกเลิก/บันทึกชิดขวา และปิดใช้งานระหว่างบันทึก', (tester) async {
    var submitted = 0;

    Widget dialog({required bool saving}) => MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AppFormDialog(
              title: 'เพิ่มกิจกรรม',
              saving: saving,
              onSubmit: () => submitted++,
              fields: const [TextField()],
            ),
          ),
        );

    await tester.pumpWidget(dialog(saving: false));
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    expect(submitted, 1);

    // ระหว่างบันทึกต้องกดซ้ำไม่ได้ และมี spinner แทนข้อความ
    await tester.pumpWidget(dialog(saving: true));
    await tester.pump();
    expect(find.text('บันทึก'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(submitted, 1);
  });

  testWidgets('AppFormDialog แสดง error ใต้ฟอร์ม', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: AppFormDialog(
          title: 'เพิ่มกิจกรรม',
          error: 'ชื่อกิจกรรมซ้ำ',
          onSubmit: () {},
          fields: const [TextField()],
        ),
      ),
    ));

    expect(find.text('ชื่อกิจกรรมซ้ำ'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
