import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/app_nav.dart';
import '../widgets/app_sidebar.dart';
import 'activities_screen.dart';
import 'activity_calendar_screen.dart';
import 'chatbot_screen.dart';
import 'evidence_review_screen.dart';
import 'hour_categories_screen.dart';
import 'my_hours_screen.dart';
import 'participations_screen.dart';
import 'register_activities_screen.dart';
import 'students_screen.dart';
import 'users_screen.dart';

/// หน้าจอปลายทางของเมนูแต่ละอัน — `null` คือหน้าแรก ซึ่งเป็น route แรกของแอป
/// อยู่แล้ว จึงกลับไปด้วยการ pop ไม่ใช่ push ทับ
Widget? screenForNavItem(AppNavItem item) => switch (item.id) {
      'home' => null,
      'register' => const RegisterActivitiesScreen(),
      'my_hours' => const MyHoursScreen(),
      'chatbot' => const ChatbotScreen(),
      'activities' => const ActivitiesScreen(),
      'participations' => const ParticipationsScreen(),
      'evidence_review' => const EvidenceReviewScreen(),
      'calendar' => const ActivityCalendarScreen(),
      'users' => const UsersScreen(),
      'hour_categories' => const HourCategoriesScreen(),
      // แดชบอร์ดคือหน้าแรกของแอดมินอยู่แล้ว กดเมนูนี้จึงแค่กลับหน้าแรก ถ้า push
      // หน้าใหม่ทับจะได้แดชบอร์ดสองใบซ้อนกันและปุ่มย้อนกลับพากลับมาที่ตัวเอง
      'dashboard' => null,
      'students' => const StudentsScreen(),
      _ => null,
    };

/// โครงหน้าจอกลางของทุกหน้า: เมนู sidebar ด้านซ้าย + แถบบนบาง ๆ + เนื้อหาของหน้านั้น
///
/// ทุกหน้าที่ผู้ใช้เข้าถึงจากเมนูให้ห่อด้วยตัวนี้ เพื่อให้โครงเหมือนกันหมดและเมนู
/// รู้เสมอว่าตอนนี้อยู่หน้าไหน (เดิมแต่ละหน้าสร้าง [AppBar] ของตัวเอง นิสิตจึงต้อง
/// กดย้อนกลับมาหน้าแรกก่อนถึงจะไปหน้าอื่นได้)
///
/// จอกว้าง sidebar กางค้างอยู่ข้างเนื้อหาและพับเก็บได้ด้วยปุ่มบนแถบบน ส่วนจอแคบ
/// sidebar ยุบเป็น drawer ที่เลื่อนออกมาเมื่อกดปุ่มเดียวกัน
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.activeId,
    required this.body,
    this.title,
  });

  /// [AppNavItem.id] ของหน้านี้
  final String activeId;

  final Widget body;

  /// ชื่อหน้าที่จะขึ้นบนแถบบน — ใส่เฉพาะหน้าที่ "ไม่มี" หัวข้อของตัวเองในเนื้อหา
  /// (เช่นหน้าแชต) หน้าที่มี SectionHeader อยู่แล้วไม่ต้องใส่ ไม่งั้นจะเห็นชื่อหน้า
  /// ซ้ำสองที่ติดกัน — แถบบนจะขึ้นชื่อระบบแทน
  final String? title;

  /// แคบกว่านี้ sidebar ยุบเป็น drawer (แท็บเล็ตแนวตั้ง 768 ก็ยุบ เพราะเมนู 210px
  /// กินพื้นที่เนื้อหาจนตารางเบียด)
  static const double wideBreakpoint = 900;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// จอกว้าง: ผู้ใช้พับ sidebar เก็บได้เพื่อเอาพื้นที่ให้ตารางกว้าง ๆ
  bool _sidebarOpen = true;

  /// ไปหน้าที่เลือกโดยไม่ให้ stack ลึกขึ้นเรื่อย ๆ
  ///
  /// กลับไปหน้าแรกก่อนเสมอแล้วค่อยเปิดหน้าใหม่ทับ — กดสลับเมนูกี่ครั้งความลึกก็
  /// ไม่เกินสองชั้น และปุ่มย้อนกลับพากลับหน้าแรกได้ตามที่ผู้ใช้คาด
  void _open(AppNavItem item) {
    // กดเมนูจาก drawer ต้องปิด drawer ก่อน ไม่งั้นเมนูค้างคาหน้าใหม่
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    if (item.id == widget.activeId) return;

    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    final screen = screenForNavItem(item);
    if (screen != null) {
      navigator.push(MaterialPageRoute(builder: (_) => screen));
    }
  }

  /// ออกจากระบบ แล้วพากลับไปหน้าแรกของ navigator จริง ๆ
  ///
  /// `authService.logout()` เฉย ๆ ไม่พอ: ทุกหน้าถูก `push` ซ้อนขึ้นมาบนหน้าแรก
  /// ตัว `home` ใน main.dart สลับเป็นหน้า login ให้แล้วก็จริง แต่มันอยู่ *ใต้* กอง
  /// route ที่ยังค้างอยู่ ผู้ใช้จึงเห็นหน้าเดิมค้างและนึกว่ากดปุ่มไม่ติด
  void _logout() {
    final navigator = Navigator.of(context);
    authService.logout();
    // ปิด drawer (ถ้าเปิดอยู่) แล้วไล่ route ที่ push ไว้ออกให้หมด
    navigator.popUntil((route) => route.isFirst);
  }

  Widget _sidebar() => AppSidebar(
        items: navItemsForRole(authService.role),
        activeId: widget.activeId,
        onSelect: _open,
        username: authService.username,
        role: authService.role,
        subtitle: navSubtitleForRole(authService.role),
        groupTitle: navGroupTitleForRole(authService.role),
        onLogout: _logout,
        onBrandTap: widget.activeId == 'home' ? null : () => _open(AppNavItem.home),
      );

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppShell.wideBreakpoint;
        final pinned = wide && _sidebarOpen;

        return Scaffold(
          key: _scaffoldKey,
          drawer: wide ? null : Drawer(width: AppSidebar.width, child: _sidebar()),
          appBar: AppTopBar(
            title: widget.title,
            username: authService.username,
            role: authService.role,
            onToggleSidebar: wide
                ? () => setState(() => _sidebarOpen = !_sidebarOpen)
                : () => _scaffoldKey.currentState?.openDrawer(),
            onBack: canPop ? () => Navigator.of(context).maybePop() : null,
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pinned) _sidebar(),
              Expanded(child: widget.body),
            ],
          ),
        );
      },
    );
  }
}

/// กรอบเนื้อหามาตรฐาน: กว้างไม่เกินขนาดที่อ่านสบาย และมีระยะขอบเท่ากันทุกหน้า
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = 1120,
    this.scrollable = true,
  });

  final Widget child;
  final double maxWidth;

  /// ปิดเมื่อเนื้อหาข้างในจัดการการเลื่อนเอง (เช่น ListView หรือหน้าแชต)
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );

    if (!scrollable) return Padding(padding: _padding, child: content);
    return SingleChildScrollView(padding: _padding, child: content);
  }

  static const EdgeInsets _padding = EdgeInsets.all(20);
}

/// โครงหน้า "จัดการข้อมูล" ของฝั่งเจ้าหน้าที่/ผู้ดูแล
///
/// ทุกหน้าจัดการมีรูปแบบเดียวกันตาม mockup: หัวข้อ + จำนวนรายการ + ปุ่มหลักมุมขวา
/// · แถวค้นหา/กรอง · เนื้อหา · แถบแบ่งหน้า — รวมไว้ที่เดียวเพื่อให้ระยะขอบและ
/// ลำดับสายตาเท่ากันหมด (เดิมแต่ละหน้าจัดเอง จึงเยื้องกันคนละไม่กี่พิกเซล)
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.activeId,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.filters = const [],
    this.busy = false,
    this.footer,
  });

  final String activeId;
  final String title;

  /// บรรทัดเล็กใต้หัวข้อ เช่น "บัญชีทั้งหมด 102 คน"
  final String? subtitle;

  /// ปุ่มหลักของหน้า (สร้าง/นำเข้า) มุมขวาของหัวข้อ
  final List<Widget> actions;

  /// ช่องค้นหาและตัวกรอง
  final List<Widget> filters;

  /// กำลังโหลดทับข้อมูลเดิม — ขึ้นแถบบางแทนการล้างเนื้อหาทิ้ง
  final bool busy;

  final Widget child;

  /// แถบแบ่งหน้า (ถ้ามี)
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeId: activeId,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(title: title, subtitle: subtitle, actions: actions),
                    if (filters.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: filters,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 2,
                child: busy ? const LinearProgressIndicator(minHeight: 2) : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: child,
                ),
              ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
