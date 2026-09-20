import 'package:activity_tracking_frontend/screens/dashboard_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/kpi_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: SizedBox(width: 280, child: child))),
    );

void main() {
  group('เกณฑ์สีของ % ผ่านเกณฑ์', () {
    test('ต่ำกว่า 50% = วิกฤต, 50–79% = เตือน, ตั้งแต่ 80% = ดี', () {
      expect(DashboardScreen.passRateTone(12), KpiTone.critical);
      expect(DashboardScreen.passRateTone(49.9), KpiTone.critical);
      expect(DashboardScreen.passRateTone(50), KpiTone.warning);
      expect(DashboardScreen.passRateTone(79.9), KpiTone.warning);
      expect(DashboardScreen.passRateTone(80), KpiTone.good);
      expect(DashboardScreen.passRateTone(100), KpiTone.good);
    });
  });

  group('ป้ายภาคเรียนบนตัวกรองแดชบอร์ด', () {
    test('ภาคต้น/ภาคปลาย แสดงเป็น "ภาคเรียนที่ 1/2" ส่วนภาคฤดูร้อนคงเดิม', () {
      expect(DashboardScreen.semesterLabels[1], 'ภาคเรียนที่ 1');
      expect(DashboardScreen.semesterLabels[2], 'ภาคเรียนที่ 2');
      expect(DashboardScreen.semesterLabels[3], 'ภาคฤดูร้อน');
    });

    test('คีย์ยังเป็น 1/2/3 ตาม gold_dim_date.semester — เปลี่ยนได้แค่ข้อความ', () {
      // คีย์คือค่าที่ยิงไปกับ query `semester=` ถ้าเพี้ยนเมื่อไหร่ตัวเลขทั้งหน้าจะกรองผิดภาค
      expect(DashboardScreen.semesterLabels.keys.toList(), [1, 2, 3]);
    });
  });

  testWidgets('KpiCard: ค่าที่ต้องเตือนใช้สีเตือน ส่วนตัวเลขกลาง ๆ ใช้สีตัวอักษรปกติ',
      (tester) async {
    await tester.pumpWidget(_wrap(const KpiCard(
      icon: Icons.verified_outlined,
      label: 'ผ่านเกณฑ์',
      value: '32%',
      sub: '32 จาก 100 คน',
      tone: KpiTone.critical,
      progress: 0.32,
    )));

    expect(find.text('32%'), findsOneWidget);
    expect(find.text('ผ่านเกณฑ์'), findsOneWidget);
    expect(find.text('32 จาก 100 คน'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final warned = tester.widget<Text>(find.text('32%')).style!.color;
    expect(warned, StatusPalette.rejected.foreground);

    await tester.pumpWidget(_wrap(const KpiCard(
      icon: Icons.groups_outlined,
      label: 'นิสิตทั้งหมด',
      value: '100',
    )));
    final neutral = tester.widget<Text>(find.text('100')).style!.color;
    expect(neutral, AppTheme.light.colorScheme.onSurface);
    // ไม่ได้ใส่ progress → ไม่มีแถบ
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('KpiCard ตัวเด่นของหน้าใช้ตัวเลขใหญ่กว่าใบอื่น', (tester) async {
    await tester.pumpWidget(_wrap(const Column(children: [
      KpiCard(icon: Icons.verified, label: 'เด่น', value: '85%', emphasized: true),
      KpiCard(icon: Icons.groups, label: 'ธรรมดา', value: '85%'),
    ])));

    final sizes = tester
        .widgetList<Text>(find.text('85%'))
        .map((t) => t.style!.fontSize!)
        .toList();
    expect(sizes.first, greaterThan(sizes.last));
  });
}
