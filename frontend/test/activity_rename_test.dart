import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/hour_category.dart';
import 'package:activity_tracking_frontend/screens/activities_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ต้องใช้ธีมจริง — ธีมของแอปตั้ง splashFactory เป็น InkRipple ส่วนดีฟอลต์ M3
// เป็น InkSparkle ที่ต้องโหลด shader asset ซึ่งไม่มีตอนรัน --no-test-assets
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

final _categories = [
  HourCategory(
    id: 1,
    name: 'ใฝ่เรียนรู้ตลอดชีวิต',
    requiredHours: 30,
    subcategories: [HourSubcategory(id: 7, name: 'กิจกรรม ICT 1', requiredHours: 10)],
  ),
];

final _existing = Activity(
  id: 5,
  name: 'ค่ายอาสาปี 2568',
  activityType: 'จิตอาสา',
  subcategoryId: 7,
  hours: 4,
  maxParticipants: 50,
  startAt: DateTime(2026, 12, 1, 9, 0),
  location: 'ห้อง SC101',
  approvalStatus: 'approved',
);

/// ช่อง "ชื่อกิจกรรม" — หาจาก label ที่อยู่ในกรอบของช่องนั้น
Finder _nameField() =>
    find.ancestor(of: find.text('ชื่อกิจกรรม'), matching: find.byType(TextField));

void main() {
  group('แก้ชื่อกิจกรรมได้ (เผื่อจัดปีถัดไปแล้วเปลี่ยนชื่อ)', () {
    testWidgets('โหมดแก้ไขเติมชื่อเดิมมาให้ และช่องชื่อต้องแก้ได้ ไม่ใช่ read-only',
        (tester) async {
      await tester.pumpWidget(
        _wrap(ActivityFormDialog(existing: _existing, categories: _categories)),
      );
      await tester.pumpAndSettle();

      expect(find.text('แก้ไขกิจกรรม'), findsOneWidget);

      final field = tester.widget<TextField>(_nameField());
      expect(field.controller!.text, 'ค่ายอาสาปี 2568');
      expect(field.readOnly, isFalse, reason: 'ช่องชื่อกิจกรรมต้องไม่ถูกล็อกเป็น read-only');
      expect(field.enabled ?? true, isTrue, reason: 'ช่องชื่อกิจกรรมต้องไม่ถูก disable');
    });

    testWidgets('พิมพ์ชื่อใหม่ทับได้ ค่าที่จะส่งไป PUT เปลี่ยนตาม', (tester) async {
      await tester.pumpWidget(
        _wrap(ActivityFormDialog(existing: _existing, categories: _categories)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_nameField(), 'ค่ายอาสาปี 2569');
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(_nameField()).controller!.text, 'ค่ายอาสาปี 2569');
      expect(find.text('ค่ายอาสาปี 2568'), findsNothing);
    });

    testWidgets('ลบชื่อจนว่างแล้วกดบันทึก ต้องเตือน ไม่ยิง API', (tester) async {
      await tester.pumpWidget(
        _wrap(ActivityFormDialog(existing: _existing, categories: _categories)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_nameField(), '   ');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('กรอกข้อมูล'), findsWidgets);
    });
  });
}
