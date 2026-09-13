import 'dart:math' as math;

import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_buttons.dart';
import 'package:activity_tracking_frontend/widgets/app_card.dart';
import 'package:activity_tracking_frontend/screens/app_shell.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/widgets/app_nav.dart';
import 'package:activity_tracking_frontend/widgets/app_sidebar.dart';
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

/// อัตราส่วน contrast ตามสูตร WCAG 2.1 (เทียบสีที่ปุ่ม "ใช้จริง" หลังธีมกลางผสมแล้ว
/// ไม่ใช่ค่าคงที่ในธีม — บั๊กขาวบนขาวเกิดจากธีมกลางทับพื้นปุ่ม ไม่ใช่ค่าสีผิด)
double _contrast(Color a, Color b) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  final la = luminance(a);
  final lb = luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

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

  group('AppSidebar', () {
    testWidgets('โลโก้ + ชื่อระบบ + หัวข้อกลุ่ม + เมนู + ผู้ใช้ท้ายแถบ', (tester) async {
      _setScreenWidth(tester, 1200);
      await tester.pumpWidget(_wrap(AppSidebar(
        items: navItemsForRole('student'),
        activeId: 'home',
        username: '662021052',
        role: 'student',
        subtitle: navSubtitleForRole('student'),
        groupTitle: navGroupTitleForRole('student'),
        onLogout: () {},
      )));

      expect(find.text('TSU'), findsOneWidget);
      expect(find.text(kAppBrandTitle), findsOneWidget);
      expect(find.text('นอกชั้นเรียน'), findsOneWidget);
      expect(find.text('เมนูนิสิต'), findsOneWidget);
      expect(find.text('หน้าแรก'), findsOneWidget);
      expect(find.text('ผู้ช่วยอัจฉริยะ'), findsOneWidget);
      // ท้ายแถบบอกว่าใครล็อกอินอยู่ พร้อมทางออกจากระบบ
      expect(find.text('662021052'), findsOneWidget);
      expect(find.text('นิสิต'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'ออกจากระบบ'), findsOneWidget);
      expect(find.text('6'), findsOneWidget, reason: 'avatar ใช้ตัวอักษรแรกของชื่อผู้ใช้');
    });

    testWidgets('ปุ่มออกจากระบบท้ายแถบอ่านออกบนพื้นน้ำเงินเข้ม และกดแล้วออกจากระบบจริง',
        (tester) async {
      _setScreenWidth(tester, 1200);
      var loggedOut = false;
      await tester.pumpWidget(_wrap(AppSidebar(
        items: navItemsForRole('student'),
        activeId: 'home',
        username: '662021052',
        role: 'student',
        onLogout: () => loggedOut = true,
      )));

      final button = find.widgetWithText(OutlinedButton, 'ออกจากระบบ');
      expect(button, findsOneWidget);
      expect(find.descendant(of: button, matching: find.byIcon(Icons.logout)), findsOneWidget);

      // ธีมกลางตั้งพื้นปุ่มเป็นสีขาว ปุ่มบนแถบเข้มจึงต้องล้างเป็นโปร่งใส ไม่งั้นได้
      // ตัวอักษร/ไอคอนขาวบนกล่องขาว = อัตราส่วน 1:1 มองไม่เห็นอะไรเลย
      //
      // ต้องอ่านจากสิ่งที่วาดออกมาจริง ไม่ใช่ `OutlinedButton.style` — ค่านั้นเก็บแค่
      // style ที่ตัวปุ่มส่งเข้ามา ส่วนของธีมกลางถูกผสมทีหลังตอน build จึงไม่โผล่ในนั้น
      final icon = find.descendant(of: button, matching: find.byIcon(Icons.logout));
      final foreground = IconTheme.of(tester.element(icon)).color!;
      final painted = tester
          .widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first)
          .color!;
      final behind = Color.alphaBlend(painted, AppColors.blueDark);
      expect(
        _contrast(foreground, behind),
        greaterThanOrEqualTo(4.5),
        reason: 'ไอคอน/ข้อความสี $foreground บนพื้นปุ่มที่วาดจริง $behind',
      );

      await tester.tap(button);
      await tester.pump();
      expect(loggedOut, isTrue);
    });

    testWidgets('เมนูที่เปิดอยู่เป็นพื้นขาวตัวน้ำเงิน ส่วนตัวอื่นเป็นตัวอักษรสว่างบนพื้นน้ำเงิน',
        (tester) async {
      _setScreenWidth(tester, 1200);
      await tester.pumpWidget(_wrap(AppSidebar(
        items: navItemsForRole('student'),
        activeId: 'register',
      )));

      expect(_styleOf(tester, 'สมัครกิจกรรม').color, AppColors.blue);
      expect(_styleOf(tester, 'สมัครกิจกรรม').fontWeight, FontWeight.w600);
      expect(_styleOf(tester, 'หน้าแรก').color, AppColors.onNav);

      final active = tester.widget<Material>(find.ancestor(
        of: find.text('สมัครกิจกรรม'),
        matching: find.byType(Material),
      ).first);
      expect(active.color, Colors.white);
    });

    testWidgets('กดเมนูแล้วส่ง item ที่กดกลับไปให้หน้าที่เรียกใช้', (tester) async {
      _setScreenWidth(tester, 1200);
      AppNavItem? picked;
      await tester.pumpWidget(_wrap(AppSidebar(
        items: navItemsForRole('admin'),
        activeId: 'activities',
        onSelect: (item) => picked = item,
      )));

      await tester.tap(find.text('แดชบอร์ด'));
      await tester.pump();
      expect(picked?.id, 'dashboard');
    });

    testWidgets('เมนูที่มีหน้าย่อยพับ/กางได้ และเปิดหน้าของตัวเองไปพร้อมกัน', (tester) async {
      _setScreenWidth(tester, 1200);
      const parent = AppNavItem(
        id: 'dashboard',
        label: 'แดชบอร์ด',
        icon: Icons.dashboard_outlined,
        children: [
          AppNavItem(id: 'dash_overview', label: 'ภาพรวม', icon: Icons.pie_chart_outline),
        ],
      );

      AppNavItem? picked;
      await tester.pumpWidget(_wrap(AppSidebar(
        items: const [parent],
        activeId: 'activities',
        onSelect: (item) => picked = item,
      )));

      // ยังไม่กาง: เห็นแค่เมนูแม่ พร้อมลูกศรบอกว่ากางได้
      expect(find.text('ภาพรวม'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      await tester.tap(find.text('แดชบอร์ด'));
      await tester.pump();
      expect(find.text('ภาพรวม'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(picked?.id, 'dashboard');

      await tester.tap(find.text('ภาพรวม'));
      await tester.pump();
      expect(picked?.id, 'dash_overview');

      // พับกลับได้
      await tester.tap(find.text('แดชบอร์ด'));
      await tester.pump();
      expect(find.text('ภาพรวม'), findsNothing);
    });

    testWidgets('หน้าย่อยที่เปิดอยู่ทำให้เมนูแม่กางเองตั้งแต่แรก', (tester) async {
      _setScreenWidth(tester, 1200);
      const parent = AppNavItem(
        id: 'dashboard',
        label: 'แดชบอร์ด',
        icon: Icons.dashboard_outlined,
        children: [
          AppNavItem(id: 'dash_stats', label: 'สถิติ', icon: Icons.query_stats),
        ],
      );

      await tester.pumpWidget(_wrap(const AppSidebar(
        items: [parent],
        activeId: 'dash_stats',
      )));

      expect(find.text('สถิติ'), findsOneWidget);
      expect(_styleOf(tester, 'สถิติ').color, AppColors.blue);
    });
  });

  group('AppTopBar', () {
    testWidgets('ปุ่มเมนู + ชื่อระบบ + กระดิ่ง + ชื่อผู้ใช้ + ป้ายบทบาท', (tester) async {
      _setScreenWidth(tester, 1200);
      var toggled = 0;
      await tester.pumpWidget(_wrap(AppTopBar(
        username: 'admin',
        role: 'admin',
        onToggleSidebar: () => toggled++,
      )));

      expect(find.byIcon(Icons.menu), findsOneWidget);
      // ไม่ได้ส่งชื่อหน้ามา แถบบนจึงขึ้นชื่อระบบแทน
      expect(find.text(kAppBrandTitle), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
      expect(find.text('ผู้ดูแลระบบ'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      expect(toggled, 1);
    });

    testWidgets('หน้าที่ไม่มีหัวข้อของตัวเองส่งชื่อหน้ามาขึ้นบนแถบได้', (tester) async {
      _setScreenWidth(tester, 1200);
      await tester.pumpWidget(_wrap(const AppTopBar(title: 'ผู้ช่วยอัจฉริยะ')));

      expect(find.text('ผู้ช่วยอัจฉริยะ'), findsOneWidget);
      expect(find.text(kAppBrandTitle), findsNothing);
    });

    testWidgets('กระดิ่งบอกตรง ๆ ว่ายังไม่มีการแจ้งเตือน ไม่ใช่ปุ่มที่กดแล้วเงียบ',
        (tester) async {
      _setScreenWidth(tester, 1200);
      await tester.pumpWidget(_wrap(const AppTopBar()));

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีการแจ้งเตือน'), findsOneWidget);
    });

    testWidgets('จอแคบซ่อนชื่อผู้ใช้ เหลือป้ายบทบาท ไม่ปล่อยให้ล้นแถบ', (tester) async {
      _setScreenWidth(tester, 360);
      await tester.pumpWidget(_wrap(AppTopBar(
        username: '662021052',
        role: 'student',
        onToggleSidebar: () {},
      )));

      expect(tester.takeException(), isNull);
      expect(find.text('662021052'), findsNothing);
      expect(find.text('นิสิต'), findsOneWidget);
    });
  });

  group('AppShell', () {
    setUp(() {
      authService.token = 'fake-token';
      authService.username = 'admin';
      authService.role = 'admin';
    });
    tearDown(() => authService.logout());

    Widget shell() => MaterialApp(
          theme: AppTheme.light,
          home: const AppShell(activeId: 'activities', body: Text('เนื้อหา')),
        );

    testWidgets('จอกว้าง: sidebar กางค้างข้างเนื้อหา และพับเก็บได้ด้วยปุ่มบนแถบบน',
        (tester) async {
      _setScreenWidth(tester, 1280);
      await tester.pumpWidget(shell());

      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.text('เมนูผู้ดูแลระบบ'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidebar), findsNothing, reason: 'พับแล้วต้องคืนพื้นที่ให้เนื้อหา');
      expect(find.text('เนื้อหา'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidebar), findsOneWidget);
    });

    testWidgets('จอแคบ: sidebar ยุบซ่อน กดปุ่มเมนูแล้วเลื่อนออกมาเป็น drawer',
        (tester) async {
      _setScreenWidth(tester, 360);
      await tester.pumpWidget(shell());

      expect(tester.takeException(), isNull);
      expect(find.byType(AppSidebar), findsNothing);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.text('จัดการผู้ใช้'), findsOneWidget);
    });

    testWidgets('แถบบนไม่มีปุ่มออกจากระบบแล้ว — ทางออกมีที่เดียวคือท้าย sidebar',
        (tester) async {
      // เคยมีสองที่ (แถบบน + ท้าย sidebar) ผู้ใช้จึงไม่แน่ใจว่าสองปุ่มต่างกันไหม
      _setScreenWidth(tester, 1280);
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppTopBar), matching: find.byIcon(Icons.logout)),
        findsNothing,
      );
      expect(find.byTooltip('ออกจากระบบ'), findsNothing);
      // ของท้าย sidebar ต้องยังอยู่
      expect(find.widgetWithText(OutlinedButton, 'ออกจากระบบ'), findsOneWidget);
    });

    testWidgets('พับ sidebar แล้วไม่เหลือปุ่มออกจากระบบบนแถบบน', (tester) async {
      _setScreenWidth(tester, 1280);
      await tester.pumpWidget(shell());
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.byType(AppSidebar), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
    });

    testWidgets('กดปุ่มท้าย sidebar แล้วออกจากระบบจริงและกลับไปหน้า login',
        (tester) async {
      // ปัญหาเดิม: ทุกหน้าถูก push ซ้อนบนหน้าแรก กด logout แล้ว home สลับเป็นหน้า
      // login ก็จริง แต่มันอยู่ใต้กอง route ที่ค้างอยู่ ผู้ใช้จึงเห็นหน้าเดิมค้าง
      _setScreenWidth(tester, 1280);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ListenableBuilder(
            listenable: authService,
            builder: (context, _) => authService.isLoggedIn
                ? const AppShell(activeId: 'home', body: Text('หน้าแรก'))
                : const Text('หน้าเข้าสู่ระบบ'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // จำลองการเปิดหน้าซ้อนขึ้นมา (เหมือนกดเมนูไปหน้าอื่น)
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const AppShell(activeId: 'activities', body: Text('เนื้อหาหน้าที่เปิดซ้อน')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('เนื้อหาหน้าที่เปิดซ้อน'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'ออกจากระบบ'));
      await tester.pumpAndSettle();

      expect(authService.isLoggedIn, isFalse);
      expect(authService.token, isNull);
      expect(find.text('หน้าเข้าสู่ระบบ'), findsOneWidget);
      expect(find.text('เนื้อหาหน้าที่เปิดซ้อน'), findsNothing,
          reason: 'หน้าที่ push ไว้ต้องถูกปิดไปด้วย ไม่ใช่ค้างทับหน้า login');
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
