import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'activities_screen.dart';
import 'activity_calendar_screen.dart';
import 'app_shell.dart';
import 'dashboard_screen.dart';
import 'hour_categories_screen.dart';
import 'participations_screen.dart';
import 'student_home_view.dart';
import 'students_screen.dart';
import 'users_screen.dart';

/// ป้ายชื่อ role ภาษาไทย (นิสิต / เจ้าหน้าที่ / ผู้ดูแลระบบ)
String roleLabel(String? role) => switch (role) {
      'student' => 'นิสิต',
      'staff' => 'เจ้าหน้าที่',
      'admin' => 'ผู้ดูแลระบบ',
      _ => '-',
    };

/// หน้าแรก — หน้าตาต่างกันตาม role
///
/// ฝั่งนิสิตเป็นหน้าโปรไฟล์ + ชั่วโมงสะสมตาม mockup ส่วนฝั่งเจ้าหน้าที่/ผู้ดูแล
/// ยังเป็นแผงเมนูเดิม (จะยกเครื่องในเฟสของฝั่งผู้ดูแล)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeId: 'home',
      body: authService.role == 'student' ? const StudentHomeView() : const _StaffHomeView(),
    );
  }
}

class _StaffHomeView extends StatelessWidget {
  const _StaffHomeView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // grid ที่ responsive: จอเล็ก 1 คอลัมน์ → จอใหญ่สุด 4 คอลัมน์
        final columns = switch (constraints.maxWidth) {
          >= 1200 => 4,
          >= 900 => 3,
          >= 600 => 2,
          _ => 1,
        };

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _WelcomeHeader(),
                  const SizedBox(height: AppSpacing.xl),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    // ความสูงคงที่แทนอัตราส่วน — อัตราส่วนทำให้การ์ดเตี้ยจนเนื้อหา
                    // ล้นบนมือถือ และสูงเว่อร์บนจอกลางที่ยังเป็นคอลัมน์เดียว
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppSpacing.lg,
                      crossAxisSpacing: AppSpacing.lg,
                      mainAxisExtent: 210,
                    ),
                    children: _menuCards(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _menuCards(BuildContext context) {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return [
      if (authService.isAdmin)
        _MenuCard(
          icon: Icons.dashboard,
          title: 'แดชบอร์ดผู้บริหาร',
          subtitle: 'ภาพรวม KPI กราฟ และกลุ่มเสี่ยง',
          onTap: () => open(const DashboardScreen()),
        ),
      if (authService.isAdmin)
        _MenuCard(
          icon: Icons.people,
          title: 'นิสิต',
          subtitle: 'จัดการข้อมูลนิสิต',
          onTap: () => open(const StudentsScreen()),
        ),
      _MenuCard(
        icon: Icons.event,
        title: 'กิจกรรม',
        subtitle: 'จัดการข้อมูลกิจกรรม',
        onTap: () => open(const ActivitiesScreen()),
      ),
      _MenuCard(
        icon: Icons.calendar_month,
        title: 'ปฏิทินกิจกรรม',
        subtitle: 'ดูว่าวันไหนมีกิจกรรมอะไรบ้าง',
        onTap: () => open(const ActivityCalendarScreen()),
      ),
      _MenuCard(
        icon: Icons.fact_check,
        title: 'การเข้าร่วมกิจกรรม',
        subtitle: 'บันทึกและตรวจสอบการเข้าร่วม',
        onTap: () => open(const ParticipationsScreen()),
      ),
      if (authService.isAdmin)
        _MenuCard(
          icon: Icons.admin_panel_settings,
          title: 'จัดการผู้ใช้',
          subtitle: 'สร้างผู้ใช้และกำหนดสิทธิ์',
          onTap: () => open(const UsersScreen()),
        ),
      if (authService.isAdmin)
        _MenuCard(
          icon: Icons.category,
          title: 'หมวดชั่วโมงกิจกรรม',
          subtitle: 'เพิ่ม/แก้ไขหมวดและหมวดย่อยที่ใช้นับชั่วโมง',
          onTap: () => open(const HourCategoriesScreen()),
        ),
    ];
  }
}

/// แถบต้อนรับ: "สวัสดี, {ผู้ใช้}" + ป้าย role
class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        gradient: const LinearGradient(
          colors: [AppColors.blueBg, AppColors.surface],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.blue,
            child: Icon(Icons.person, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สวัสดี, ${authService.username ?? ''}',
                  style: theme.textTheme.titleLarge?.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        roleLabel(authService.role),
                        style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
                      ),
                    ),
                    Text(
                      'ระบบติดตามการเข้าร่วมกิจกรรมนิสิต',
                      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.sub),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          elevation: _hovered ? 4 : 1,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: _hovered ? AppColors.blue : AppColors.blueBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      size: 30,
                      color: _hovered ? Colors.white : AppColors.blue,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
