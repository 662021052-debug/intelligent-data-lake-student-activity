import 'package:activity_tracking_frontend/models/hour_summary.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/hour_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HourCategorySummary _category({
  required int id,
  required String name,
  required double required_,
  required double earned,
  required bool completed,
}) =>
    HourCategorySummary(
      id: id,
      name: name,
      requiredHours: required_,
      earnedHours: earned,
      completed: completed,
      subcategories: [
        HourSubcategorySummary(
          id: id * 10,
          name: '$name ย่อย',
          requiredHours: required_,
          earnedHours: earned,
          completed: completed,
        ),
      ],
    );

final _categories = [
  _category(id: 1, name: 'ใฝ่เรียนรู้ตลอดชีวิต', required_: 12, earned: 12, completed: true),
  _category(id: 2, name: 'จิตอาสา', required_: 12, earned: 3, completed: false),
];

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('โหมดปกติมีการ์ดสรุปรวมทุกหมวด', (tester) async {
    await tester.pumpWidget(_wrap(HourSummaryView(categories: _categories)));

    expect(find.text('รวมทุกหมวด'), findsOneWidget);
    expect(find.text('15 / 24 ชั่วโมง'), findsOneWidget);
  });

  testWidgets('โหมด embedded ตัดการ์ดสรุปรวมออก (แดชบอร์ดมี KPI อยู่แล้ว)', (tester) async {
    await tester.pumpWidget(_wrap(
      SingleChildScrollView(child: HourSummaryView(categories: _categories, embedded: true)),
    ));

    expect(find.text('รวมทุกหมวด'), findsNothing);
    // แต่ยังต้องเห็นรายละเอียดรายหมวดครบ
    expect(find.text('ใฝ่เรียนรู้ตลอดชีวิต'), findsOneWidget);
    expect(find.text('จิตอาสา'), findsOneWidget);
    expect(find.text('12 / 12 ชม.'), findsOneWidget);
    expect(find.text('3 / 12 ชม.'), findsOneWidget);
  });

  testWidgets('หมวดที่ครบแล้วมีไอคอนติ๊ก หมวดที่ยังไม่ครบไม่มี', (tester) async {
    await tester.pumpWidget(_wrap(
      SingleChildScrollView(
        child: HourSummaryView(
          categories: _categories,
          embedded: true,
          showSubcategories: false,
        ),
      ),
    ));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
