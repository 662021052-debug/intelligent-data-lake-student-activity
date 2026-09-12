import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/admin_console.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('ConsoleShortcutBar', () {
    testWidgets('แสดงปุ่มลัดครบทุกอันและกดแล้วเรียก onTap', (tester) async {
      var tapped = '';
      await tester.pumpWidget(_wrap(ConsoleShortcutBar(
        shortcuts: [
          ConsoleShortcut(
            icon: Icons.event_outlined,
            label: 'จัดการกิจกรรม',
            onTap: () => tapped = 'activities',
          ),
          ConsoleShortcut(
            icon: Icons.sync,
            label: 'รีเฟรช Gold',
            onTap: () => tapped = 'gold',
          ),
        ],
      )));

      expect(find.widgetWithText(OutlinedButton, 'จัดการกิจกรรม'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'รีเฟรช Gold'));
      expect(tapped, 'gold');
    });

    testWidgets('ปุ่มที่กำลังทำงานอยู่ถูกปิดและขึ้นวงหมุนแทนไอคอน', (tester) async {
      await tester.pumpWidget(_wrap(ConsoleShortcutBar(
        shortcuts: [
          ConsoleShortcut(icon: Icons.sync, label: 'รีเฟรช Gold', onTap: () {}, busy: true),
        ],
      )));

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'รีเฟรช Gold'),
      );
      expect(button.onPressed, isNull, reason: 'กดซ้ำระหว่างรออาจยิงซ้ำ');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsNothing);
    });
  });

  group('GuideBanner', () {
    testWidgets('ปุ่ม "เปิดคู่มือ" ต้องพาไปคู่มือจริง ไม่ใช่ปุ่มที่กดแล้วเงียบ',
        (tester) async {
      var opened = false;
      await tester.pumpWidget(_wrap(GuideBanner(onOpen: () => opened = true)));

      expect(find.text('คู่มือการใช้งานสำหรับ Admin'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'เปิดคู่มือ →'));
      expect(opened, isTrue);
    });

    test('คู่มือมีเนื้อหาจริงทุกหัวข้อ', () {
      expect(adminGuideSections, isNotEmpty);
      for (final section in adminGuideSections) {
        expect(section.title.trim(), isNotEmpty);
        expect(section.body.trim().length, greaterThan(40), reason: section.title);
      }
    });

    testWidgets('กดเปิดคู่มือแล้วเห็นหัวข้อทั้งหมดในกล่อง', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => GuideBanner(onOpen: () => showAdminGuide(context)),
          ),
        ),
      ));

      await tester.tap(find.widgetWithText(FilledButton, 'เปิดคู่มือ →'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      for (final section in adminGuideSections) {
        expect(find.text(section.title), findsOneWidget, reason: section.title);
      }
    });
  });

  group('StatusOverviewCard', () {
    testWidgets('แสดงคิวงานทั้งสามตัวพร้อมจำนวน', (tester) async {
      await tester.pumpWidget(_wrap(const StatusOverviewCard(
        counts: ConsoleCounts(pendingActivities: 3, pendingEvidence: 12, approvedToday: 5),
      )));

      expect(find.text('ภาพรวมสถานะ'), findsOneWidget);
      expect(find.text('รออนุมัติกิจกรรม'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('หลักฐานรอตรวจ'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('อนุมัติแล้ววันนี้'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });
  });

  group('TodoCard', () {
    testWidgets('ซ่อนงานที่เหลือศูนย์ และกดแล้วไปหน้าที่เกี่ยว', (tester) async {
      var tapped = '';
      await tester.pumpWidget(_wrap(TodoCard(
        items: [
          TodoItem(
            label: 'อนุมัติกิจกรรมที่รออยู่',
            count: 2,
            onTap: () => tapped = 'activities',
          ),
          TodoItem(
            label: 'ตรวจหลักฐานการเข้าร่วม',
            count: 0,
            onTap: () => tapped = 'evidence',
          ),
        ],
      )));

      // งานที่ไม่เหลือแล้วต้องไม่ขึ้นเป็นรายการให้กด — กดไปก็ไม่มีอะไรให้ทำ
      expect(find.text('อนุมัติกิจกรรมที่รออยู่'), findsOneWidget);
      expect(find.text('ตรวจหลักฐานการเข้าร่วม'), findsNothing);

      await tester.tap(find.text('อนุมัติกิจกรรมที่รออยู่'));
      expect(tapped, 'activities');
    });

    testWidgets('ไม่มีงานค้างเลยก็บอกตรง ๆ แทนที่จะเป็นการ์ดว่าง', (tester) async {
      await tester.pumpWidget(_wrap(TodoCard(
        items: [
          TodoItem(label: 'อนุมัติกิจกรรม', count: 0, onTap: () {}),
        ],
      )));

      expect(find.textContaining('เคลียร์หมดแล้ว'), findsOneWidget);
      expect(find.text('ดู →'), findsNothing, reason: 'ไม่มีงานก็ไม่ควรมีลิงก์ให้กด');
    });
  });

  group('ConsoleCounts', () {
    test('outstanding รวมเฉพาะงานที่ยังค้าง ไม่รวมงานที่ทำไปแล้ววันนี้', () {
      const counts =
          ConsoleCounts(pendingActivities: 3, pendingEvidence: 12, approvedToday: 5);
      expect(counts.outstanding, 15);
    });
  });
}
