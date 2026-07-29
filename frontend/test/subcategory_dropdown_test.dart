import 'package:activity_tracking_frontend/models/hour_category.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/subcategory_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// หมวดที่ชื่อยาวมาก — เคสที่ทำให้ช่อง "หมวดชั่วโมง" ล้นกรอบ dialog (บั๊ก E3)
final _categories = [
  HourCategory(
    id: 1,
    name: 'กิจกรรมเพื่อสังคมและบำเพ็ญประโยชน์ต่อส่วนรวม',
    requiredHours: 30,
    subcategories: [
      HourSubcategory(id: 11, name: 'จิตอาสาพัฒนาชุมชน', requiredHours: 15),
      HourSubcategory(id: 12, name: 'บริจาคโลหิต', requiredHours: 15),
    ],
  ),
  HourCategory(
    id: 2,
    name: 'กิจกรรมเสริมสร้างสมรรถนะ',
    requiredHours: 30,
    subcategories: [
      HourSubcategory(id: 21, name: 'อบรมทักษะดิจิทัล', requiredHours: 30),
    ],
  ),
];

Widget _wrap(Widget child, {double width = 260}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  testWidgets('ช่องที่ปิดอยู่แสดงชื่อหมวดย่อยสั้น ๆ ไม่ใช่ path เต็ม', (tester) async {
    await tester.pumpWidget(_wrap(SubcategoryDropdown(
      categories: _categories,
      value: 11,
      onChanged: (_) {},
    )));

    // ชื่อสั้นอยู่ในช่อง ส่วนชื่อหมวดแม่ถูกย้ายไปเป็น helper ใต้ช่อง
    expect(find.text('จิตอาสาพัฒนาชุมชน'), findsOneWidget);
    expect(find.text('กิจกรรมเพื่อสังคมและบำเพ็ญประโยชน์ต่อส่วนรวม'), findsOneWidget);
    // path เต็มแบบเดิม (ที่เคยล้นกรอบ) ต้องไม่ถูกแสดงในช่อง
    expect(
      find.text('กิจกรรมเพื่อสังคมและบำเพ็ญประโยชน์ต่อส่วนรวม › จิตอาสาพัฒนาชุมชน'),
      findsNothing,
    );
  });

  testWidgets('ชื่อยาวในกรอบแคบไม่ทำให้ layout ล้น', (tester) async {
    // ถ้าข้อความล้นกรอบ Flutter จะโยน FlutterError ตอน pump → เทสต์ตกทันที
    await tester.pumpWidget(_wrap(
      SubcategoryDropdown(
        categories: _categories,
        value: 11,
        onChanged: (_) {},
      ),
      width: 180,
    ));

    expect(tester.takeException(), isNull);
  });

  testWidgets('กางรายการแล้วเห็นชื่อเต็มทุกหมวดย่อย และเลือกได้', (tester) async {
    int? selected;
    await tester.pumpWidget(_wrap(SubcategoryDropdown(
      categories: _categories,
      value: 11,
      onChanged: (v) => selected = v,
    )));

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();

    expect(find.text('กิจกรรมเสริมสร้างสมรรถนะ › อบรมทักษะดิจิทัล'), findsOneWidget);

    await tester.tap(find.text('กิจกรรมเสริมสร้างสมรรถนะ › อบรมทักษะดิจิทัล').last);
    await tester.pumpAndSettle();

    expect(selected, 21);
  });

  testWidgets('ยังไม่ได้เลือก → validator ไม่ให้บันทึก', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(_wrap(Form(
      key: formKey,
      child: SubcategoryDropdown(
        categories: _categories,
        value: null,
        onChanged: (_) {},
      ),
    )));

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('กรุณาเลือกหมวดชั่วโมง'), findsOneWidget);
  });
}
