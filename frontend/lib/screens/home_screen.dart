import 'package:flutter/material.dart';

import '../models/hour_summary.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'activities_screen.dart';
import 'chatbot_screen.dart';
import 'dashboard_screen.dart';
import 'my_hours_screen.dart';
import 'participations_screen.dart';
import 'register_activities_screen.dart';
import 'students_screen.dart';
import 'users_screen.dart';

/// ป้ายชื่อ role ภาษาไทย (นิสิต / เจ้าหน้าที่ / ผู้ดูแลระบบ)
String roleLabel(String? role) => switch (role) {
      'student' => 'นิสิต',
      'staff' => 'เจ้าหน้าที่',
      'admin' => 'ผู้ดูแลระบบ',
      _ => '-',
    };

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isStudent = authService.role == 'student';

    return Scaffold(
      appBar: AppBar(
        title: const Text('หน้าหลัก'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('ออกจากระบบ'),
              onPressed: authService.logout,
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // grid ที่ responsive: จอเล็ก 1 คอลัมน์ → จอใหญ่สุด 4 คอลัมน์
          final width = constraints.maxWidth;
          final columns = switch (width) {
            >= 1200 => 4,
            >= 900 => 3,
            >= 600 => 2,
            _ => 1,
          };
          final cards = _menuCards(context, isStudent);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _WelcomeHeader(),
                    if (isStudent) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const _MyHoursSummaryCard(),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.lg,
                      crossAxisSpacing: AppSpacing.lg,
                      childAspectRatio: columns == 1 ? 2.6 : 1.25,
                      children: cards,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _menuCards(BuildContext context, bool isStudent) {
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
        subtitle: isStudent ? 'ดูกิจกรรมทั้งหมด' : 'จัดการข้อมูลกิจกรรม',
        onTap: () => open(const ActivitiesScreen()),
      ),
      _MenuCard(
        icon: Icons.fact_check,
        title: 'การเข้าร่วมกิจกรรม',
        subtitle: isStudent
            ? 'ดูประวัติการเข้าร่วมและส่งหลักฐาน'
            : 'บันทึกและตรวจสอบการเข้าร่วม',
        onTap: () => open(const ParticipationsScreen()),
      ),
      if (authService.isAdmin)
        _MenuCard(
          icon: Icons.admin_panel_settings,
          title: 'จัดการผู้ใช้',
          subtitle: 'สร้างผู้ใช้และกำหนดสิทธิ์',
          onTap: () => open(const UsersScreen()),
        ),
      if (isStudent)
        _MenuCard(
          icon: Icons.how_to_reg,
          title: 'สมัครกิจกรรม',
          subtitle: 'ดูกิจกรรมที่เปิดรับสมัครและสมัครเข้าร่วม',
          onTap: () => open(const RegisterActivitiesScreen()),
        ),
      if (isStudent)
        _MenuCard(
          icon: Icons.emoji_events,
          title: 'แดชบอร์ดชั่วโมงของฉัน',
          subtitle: 'สรุปชั่วโมงรวม กราฟรายหมวด และสิ่งที่ยังขาด',
          onTap: () => open(const MyHoursScreen()),
        ),
      if (isStudent)
        _MenuCard(
          icon: Icons.smart_toy,
          title: 'ผู้ช่วยอัจฉริยะ',
          subtitle: 'ถามชั่วโมง หมวดที่ยังขาด และขอคำแนะนำกิจกรรม',
          onTap: () => open(const ChatbotScreen()),
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
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: scheme.primary,
            child: Icon(Icons.person, color: scheme.onPrimary, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สวัสดี, ${authService.username ?? ''}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
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
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        roleLabel(authService.role),
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      'ระบบติดตามการเข้าร่วมกิจกรรมนิสิต',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onPrimaryContainer),
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

/// การ์ดสรุปชั่วโมงสะสมของนิสิต (X/60 + แถบ progress) — เห็นสถานะตัวเองทันทีที่เข้า
///
/// โหลดไม่ได้ (ออฟไลน์ / ยังไม่ผูกข้อมูลนิสิต) ให้ซ่อนการ์ดไปเงียบ ๆ แทนที่จะโชว์ error
/// เพราะเป็นแค่ข้อมูลเสริมบนหน้าหลัก ไม่ใช่เนื้อหาหลักของหน้า
class _MyHoursSummaryCard extends StatefulWidget {
  const _MyHoursSummaryCard();

  @override
  State<_MyHoursSummaryCard> createState() => _MyHoursSummaryCardState();
}

class _MyHoursSummaryCardState extends State<_MyHoursSummaryCard> {
  late final Future<List<HourCategorySummary>> _future = ApiService.fetchList(
    '/students/me/hours-summary',
    HourCategorySummary.fromJson,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HourCategorySummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final categories = snapshot.data!;
        final earned = categories.fold<double>(0, (sum, c) => sum + c.earnedHours);
        final required = categories.fold<double>(0, (sum, c) => sum + c.requiredHours);
        final progress = required == 0 ? 0.0 : (earned / required).clamp(0.0, 1.0);
        final done = categories.where((c) => c.completed).length;

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final passed = earned >= required && required > 0;
        final barColor = passed
            ? StatusPalette.approved.foreground
            : progress >= 0.5
                ? scheme.primary
                : StatusPalette.pending.foreground;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timelapse, color: scheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text('ชั่วโมงสะสมของฉัน', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text(
                      '${_trim(earned)}/${_trim(required)} ชม.',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: barColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  passed
                      ? 'ครบเกณฑ์แล้ว 🎉 (ผ่าน $done/${categories.length} หมวด)'
                      : 'ยังขาดอีก ${_trim(required - earned)} ชม. • ผ่านแล้ว $done/${categories.length} หมวด',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _trim(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();
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
    final scheme = theme.colorScheme;

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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: _hovered ? scheme.primary : scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      size: 30,
                      color: _hovered ? scheme.onPrimary : scheme.onPrimaryContainer,
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
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
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
