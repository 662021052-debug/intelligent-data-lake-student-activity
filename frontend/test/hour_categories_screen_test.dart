import 'package:activity_tracking_frontend/models/hour_category.dart';
import 'package:activity_tracking_frontend/screens/hour_categories_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ธีมจริงตั้ง splashFactory เป็น InkRipple ส่วนดีฟอลต์ M3 เป็น InkSparkle ที่ต้อง
// โหลด shader asset ซึ่งไม่มีตอนรัน --no-test-assets
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

final _categories = [
  HourCategory(
    id: 1,
    name: 'พัฒนาทักษะชีวิต',
    requiredHours: 12,
    subcategories: [
      HourSubcategory(id: 10, name: 'กิจกรรมบูรณาการ 1', requiredHours: 4),
    ],
  ),
  HourCategory(id: 2, name: 'TSU รับใช้สังคม', requiredHours: 12, subcategories: []),
];

void main() {
  group('สิทธิ์เข้าหน้าจัดการหมวดชั่วโมง', () {
    tearDown(() => authService.logout());

    // ต้องกันตั้งแต่หน้าจอ ไม่ใช่รอให้ backend ตอบ 403 — ไม่งั้น initState ยิง API
    // ไปแล้วผู้ใช้เห็นหน้าเปล่ากับ error แทนคำอธิบายว่าเข้าไม่ได้เพราะอะไร
    for (final role in ['staff', 'student']) {
      testWidgets('$role เข้าไม่ได้', (tester) async {
        authService.token = 'fake-token';
        authService.username = role;
        authService.role = role;

        await tester.pumpWidget(const MaterialApp(home: HourCategoriesScreen()));

        expect(find.text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้'), findsOneWidget);
      });
    }
  });

  group('ตรวจช่องชั่วโมงที่ต้องการ', () {
    test('ว่าง / ไม่ใช่ตัวเลข / <= 0 ต้องไม่ผ่าน', () {
      expect(requiredHoursValidator(null), 'กรอกจำนวนชั่วโมง');
      expect(requiredHoursValidator('   '), 'กรอกจำนวนชั่วโมง');
      expect(requiredHoursValidator('สี่'), 'กรอกเป็นตัวเลข');
      expect(requiredHoursValidator('0'), 'ชั่วโมงต้องมากกว่า 0');
      expect(requiredHoursValidator('-4'), 'ชั่วโมงต้องมากกว่า 0');
    });

    test('ตัวเลขบวก (รวมทศนิยม) ผ่าน', () {
      expect(requiredHoursValidator('12'), isNull);
      expect(requiredHoursValidator('1.5'), isNull);
      expect(requiredHoursValidator(' 8 '), isNull);
    });
  });

  group('dialog หมวดใหญ่', () {
    testWidgets('เพิ่มหมวด: ช่องว่างเปล่า และมีทั้งชื่อหมวดกับชั่วโมง', (tester) async {
      await tester.pumpWidget(_wrap(const HourCategoryFormDialog()));
      await tester.pumpAndSettle();

      expect(find.text('เพิ่มหมวดชั่วโมง'), findsOneWidget);
      expect(find.text('ชื่อหมวด'), findsOneWidget);
      expect(find.text('ชั่วโมงที่ต้องการ'), findsOneWidget);
    });

    testWidgets('แก้ไขหมวด: เติมค่าเดิมให้ครบ และชั่วโมงไม่มี .0 ห้อยท้าย', (tester) async {
      await tester.pumpWidget(_wrap(HourCategoryFormDialog(existing: _categories.first)));
      await tester.pumpAndSettle();

      expect(find.text('แก้ไขหมวดชั่วโมง'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'พัฒนาทักษะชีวิต'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '12'), findsOneWidget);
    });

    testWidgets('กดบันทึกทั้งที่ยังไม่กรอก ต้องขึ้น error ไม่ยิง API', (tester) async {
      await tester.pumpWidget(_wrap(const HourCategoryFormDialog()));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('กรอกข้อมูล'), findsOneWidget);
      expect(find.text('กรอกจำนวนชั่วโมง'), findsOneWidget);
    });

    testWidgets('ชั่วโมง 0 ไม่ผ่านตั้งแต่ในฟอร์ม (backend ก็ตอบ 422)', (tester) async {
      await tester.pumpWidget(_wrap(const HourCategoryFormDialog()));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'ชื่อหมวด'), 'หมวดใหม่');
      await tester.enterText(find.widgetWithText(TextFormField, 'ชั่วโมงที่ต้องการ'), '0');
      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('ชั่วโมงต้องมากกว่า 0'), findsOneWidget);
    });
  });

  group('dialog หมวดย่อย', () {
    testWidgets('เปิดจากหมวดไหน dropdown ต้องตั้งไว้ที่หมวดนั้น', (tester) async {
      await tester.pumpWidget(_wrap(
        HourSubcategoryFormDialog(categories: _categories, categoryId: 2),
      ));
      await tester.pumpAndSettle();

      expect(find.text('เพิ่มหมวดย่อย'), findsOneWidget);
      expect(find.text('อยู่ใต้หมวด'), findsOneWidget);
      expect(find.text('TSU รับใช้สังคม'), findsOneWidget);
    });

    testWidgets('ย้ายหมวดย่อยไปหมวดอื่นได้ — dropdown มีทุกหมวดให้เลือก', (tester) async {
      await tester.pumpWidget(_wrap(
        HourSubcategoryFormDialog(
          categories: _categories,
          categoryId: 1,
          existing: _categories.first.subcategories.first,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('แก้ไขหมวดย่อย'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'กิจกรรมบูรณาการ 1'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.text('TSU รับใช้สังคม'), findsWidgets);
    });

    testWidgets('กดบันทึกทั้งที่ยังไม่กรอก ต้องขึ้น error ไม่ยิง API', (tester) async {
      await tester.pumpWidget(_wrap(
        HourSubcategoryFormDialog(categories: _categories, categoryId: 1),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('กรอกข้อมูล'), findsOneWidget);
      expect(find.text('กรอกจำนวนชั่วโมง'), findsOneWidget);
    });
  });
}
