import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_buttons.dart';
import 'package:activity_tracking_frontend/widgets/app_card.dart';
import 'package:activity_tracking_frontend/widgets/app_nav_bar.dart';
import 'package:activity_tracking_frontend/widgets/empty_state.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );

/// กำหนดความกว้างจอของเทสต์ — แถบนำทางเปลี่ยนรูปแบบตามความกว้างที่ได้รับจริง
/// (ครอบด้วย SizedBox ไม่ได้ผล เพราะจอเทสต์กว้าง 800 จะบีบกลับมาเท่าเดิม)
void _setScreenWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  group('เมนูตาม role', () {
    test('นิสิตเห็นเมนูฝั่งนิสิต ไม่มีเมนูผู้ดูแล', () {
      final ids = navItemsForRole('student').map((i) => i.id);
      expect(ids, containsAll(<String>['home', 'register', 'my_hours', 'chatbot']));
      expect(ids, isNot(contains('users')));
      expect(ids, isNot(contains('dashboard')));
    });

    test('แอดมินเห็นเมนูผู้ดูแลครบ', () {
      final ids = navItemsForRole('admin').map((i) => i.id);
      expect(ids, containsAll(<String>['activities', 'users', 'hour_categories', 'dashboard']));
    });

    test('เจ้าหน้าที่ไม่เห็นเมนูที่เป็นของแอดมินเท่านั้น', () {
      final ids = navItemsForRole('staff').map((i) => i.id);
      expect(ids, contains('activities'));
      expect(ids, isNot(contains('users')));
      expect(ids, isNot(contains('hour_categories')));
      expect(ids, isNot(contains('dashboard')));
    });
  });

  group('AppNavBar', () {
    testWidgets('จอกว้าง: โลโก้ + ชื่อระบบ + เมนูแนวนอน + ปุ่มออกจากระบบ', (tester) async {
      _setScreenWidth(tester, 1200);
      await tester.pumpWidget(_wrap(AppNavBar(
        items: navItemsForRole('student'),
        activeId: 'home',
        username: '662021052',
        subtitle: navSubtitleForRole('student'),
        onLogout: () {},
      )));

      expect(find.text('TSU'), findsOneWidget);
      expect(find.text(kAppBrandTitle), findsOneWidget);
      expect(find.text('นอกชั้นเรียน'), findsOneWidget);
      expect(find.text('หน้าแรก'), findsOneWidget);
      expect(find.text('ผู้ช่วยอัจฉริยะ'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'ออกจากระบบ'), findsOneWidget);
      expect(find.text('6'), findsOneWidget, reason: 'avatar ใช้ตัวอักษรแรกของชื่อผู้ใช้');
    });

    testWidgets('เมนูที่เปิดอยู่เป็นสีฟ้าตัวหนา ส่วนเมนูอื่นเป็นเทา', (tester) async {
      _setScreenWidth(tester, 1200);
      await tester.pumpWidget(_wrap(AppNavBar(
        items: navItemsForRole('student'),
        activeId: 'register',
      )));

      expect(_styleOf(tester, 'สมัครกิจกรรม').color, AppColors.blue);
      expect(_styleOf(tester, 'สมัครกิจกรรม').fontWeight, FontWeight.w600);
      expect(_styleOf(tester, 'หน้าแรก').color, AppColors.sub);
    });

    testWidgets('กดเมนูแล้วส่ง item ที่กดกลับไปให้หน้าที่เรียกใช้', (tester) async {
      _setScreenWidth(tester, 1200);
      AppNavItem? picked;
      await tester.pumpWidget(_wrap(AppNavBar(
        items: navItemsForRole('admin'),
        activeId: 'activities',
        onSelect: (item) => picked = item,
      )));

      await tester.tap(find.text('แดชบอร์ด'));
      await tester.pump();
      expect(picked?.id, 'dashboard');
    });

    testWidgets('จอแคบ: ยุบเมนูเป็นปุ่มเมนู ไม่ปล่อยให้ล้นแถบ', (tester) async {
      _setScreenWidth(tester, 600);
      await tester.pumpWidget(_wrap(
        AppNavBar(items: navItemsForRole('admin'), activeId: 'users', onLogout: () {}),
      ));

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.text('หมวดชั่วโมง'), findsNothing, reason: 'เมนูย้ายไปอยู่ใน popup');

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('หมวดชั่วโมง'), findsOneWidget);
    });
  });

  group('คอมโพเนนต์กลางอื่น ๆ', () {
    testWidgets('StatusChip เป็นทรงแคปซูลและใช้สีตามสถานะ', (tester) async {
      await tester.pumpWidget(_wrap(const StatusChip(
        label: 'อนุมัติแล้ว',
        palette: StatusPalette.approved,
      )));

      final decoration = tester
          .widget<Container>(find.ancestor(
            of: find.text('อนุมัติแล้ว'),
            matching: find.byType(Container),
          ).first)
          .decoration as BoxDecoration;

      expect(decoration.color, StatusPalette.approved.background);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AppRadius.pill),
        reason: 'ชิปสถานะต้องเป็น pill ตาม mockup',
      );
      expect(_styleOf(tester, 'อนุมัติแล้ว').color, StatusPalette.approved.foreground);
    });

    testWidgets('AppIconButton มี tooltip เสมอ และตัวลบใช้สีแดง', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(Row(children: [
        AppIconButton(icon: Icons.edit, tooltip: 'แก้ไข', onPressed: () => taps++),
        AppIconButton(icon: Icons.delete, tooltip: 'ลบ', danger: true, onPressed: () {}),
      ])));

      expect(find.byTooltip('แก้ไข'), findsOneWidget);
      expect(find.byTooltip('ลบ'), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.delete)).color, AppColors.danger);
      expect(tester.widget<Icon>(find.byIcon(Icons.edit)).color, AppColors.sub);

      await tester.tap(find.byIcon(Icons.edit));
      expect(taps, 1);
    });

    testWidgets('SectionHeader แสดงชื่อเรื่อง คำอธิบาย และปุ่มด้านขวา', (tester) async {
      await tester.pumpWidget(_wrap(SectionHeader(
        title: 'จัดการกิจกรรม',
        subtitle: 'ปีการศึกษา 2569 · 33 กิจกรรม',
        actions: [FilledButton(onPressed: () {}, child: const Text('สร้างกิจกรรม'))],
      )));

      expect(find.text('จัดการกิจกรรม'), findsOneWidget);
      expect(find.text('ปีการศึกษา 2569 · 33 กิจกรรม'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'สร้างกิจกรรม'), findsOneWidget);
    });

    testWidgets('ProgressRow เลือกสีแถบตามความคืบหน้า', (tester) async {
      expect(ProgressRow.barColor(1), StatusPalette.approved.accent);
      expect(ProgressRow.barColor(0.6), AppColors.blue);
      expect(ProgressRow.barColor(0.2), StatusPalette.pending.accent);

      await tester.pumpWidget(_wrap(const ProgressRow(
        label: 'ใฝ่เรียนรู้ตลอดชีวิต',
        value: '8/20',
        progress: 0.4,
      )));

      expect(find.text('ใฝ่เรียนรู้ตลอดชีวิต'), findsOneWidget);
      expect(find.text('8/20'), findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value,
        0.4,
      );
    });

    testWidgets('LoadingState มีวงหมุนพร้อมข้อความไทย', (tester) async {
      await tester.pumpWidget(_wrap(const LoadingState()));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('กำลังโหลดข้อมูล...'), findsOneWidget);
    });
  });

  group('ธีมกลาง', () {
    test('ใช้สีประจำมหาวิทยาลัย (เทา-ฟ้า) และพื้นหน้าเป็นเทาอ่อน', () {
      final theme = AppTheme.light;
      expect(theme.colorScheme.primary, AppColors.blue);
      expect(theme.colorScheme.onSurface, AppColors.ink);
      expect(theme.colorScheme.outlineVariant, AppColors.line);
      expect(theme.scaffoldBackgroundColor, AppColors.page);
      expect(theme.cardTheme.color, AppColors.surface);
    });

    test('ใช้ฟอนต์ Sarabun ทั้งแอป', () {
      final family = AppTheme.light.textTheme.bodyMedium?.fontFamily ?? '';
      expect(family, contains('Sarabun'));
    });

    test('มุมโค้ง: การ์ด 12 · ปุ่มและช่องกรอก 8', () {
      expect(AppRadius.card, 12);
      expect(AppRadius.field, 8);

      final cardShape = AppTheme.light.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.borderRadius, BorderRadius.circular(AppRadius.card));
    });
  });
}
