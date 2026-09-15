import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_summary.dart';
import '../models/participation.dart';
import '../models/student.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/kpi_card.dart';
import '../widgets/student_dashboard.dart';
import 'activities_screen.dart';
import 'activity_calendar_screen.dart';
import 'checkin_scan_screen.dart';
import 'my_hours_screen.dart';
import 'participations_screen.dart';

/// หน้าแรกของนิสิต = แดชบอร์ดส่วนตัวตาม mockup หน้า 2
///
/// แถวต้อนรับ · KPI 4 ใบ · ชั่วโมงตาม Talent/PLO · การ์ดแนะนำกิจกรรม · ทางลัด
/// ตาราง "กิจกรรมที่เข้าร่วม" ย้ายไปหน้ารายละเอียดชั่วโมงแล้ว (ไม่ได้ลบทิ้ง)
///
/// ทุกอย่างมาจาก endpoint ที่มีอยู่แล้ว ไม่ได้เพิ่ม/แก้ API:
/// - `/students/me/hours-summary` ชั่วโมงแยกตาม Talent → รายการเกณฑ์
/// - `/activities` กิจกรรมทั้งหมด (ใช้หาว่ากิจกรรมที่สมัครไว้จัดวันไหน)
/// - `/participations` รายการที่ตัวเองเข้าร่วม
/// - `/students/{id}` ชื่อ-คณะ (นิสิตอ่านของตัวเองได้) โดยรู้ id จาก participation
class StudentHomeView extends StatefulWidget {
  const StudentHomeView({super.key});

  @override
  State<StudentHomeView> createState() => _StudentHomeViewState();
}

class _StudentHomeViewState extends State<StudentHomeView> {
  List<HourCategorySummary> _talents = [];
  List<Participation> _participations = [];
  List<Activity> _activities = [];
  Student? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final talents = await ApiService.fetchList(
        '/students/me/hours-summary',
        HourCategorySummary.fromJson,
      );
      final participations = await ApiService.fetchAll('/participations', Participation.fromJson);
      final activities = await ApiService.fetchAll('/activities', Activity.fromJson);
      if (!mounted) return;
      setState(() {
        _talents = talents;
        _participations = participations;
        _activities = activities;
      });
      await _loadProfile(participations);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ชื่อ-คณะของตัวเอง — ระบบไม่มี `/students/me` และ JWT พกมาแค่ username กับ role
  /// จึงต้องรู้ id ของตัวเองจาก participation ก่อน
  ///
  /// ยังไม่เคยเข้าร่วมกิจกรรมเลยก็จะไม่มี id ให้ถาม — แถวต้อนรับจะโชว์เท่าที่รู้
  /// (รหัสนิสิตจาก username) ซึ่งยังใช้งานได้ ไม่ใช่เหตุให้ทั้งหน้าพัง
  Future<void> _loadProfile(List<Participation> participations) async {
    if (participations.isEmpty) return;
    try {
      final profile = await ApiService.fetchObject(
        '/students/${participations.first.studentId}',
        Student.fromJson,
      );
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // อ่านโปรไฟล์ไม่ได้ถือว่าเป็นข้อมูลเสริม ไม่ทำให้หน้าแรกใช้ไม่ได้
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDashboard(),
                const SizedBox(height: AppSpacing.xl),
                // ทางลัดไม่ขึ้นกับข้อมูลที่ต้องโหลด จึงอยู่นอกส่วนที่รอโหลด —
                // นิสิตกดไปหน้าอื่นได้ทันทีแม้ตอนนั้นเครือข่ายจะยังไม่ตอบ
                const _ShortcutSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    // ใช้ความสูง "อย่างน้อย" ไม่ใช่ความสูงตายตัว — บนจอแคบข้อความจะขึ้นหลายบรรทัด
    // แล้วล้นกรอบที่ตั้งไว้
    if (_loading) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220),
        child: LoadingState(message: 'กำลังโหลดข้อมูลของคุณ...'),
      );
    }
    if (_error != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220),
        child: ErrorState(message: _error!, onRetry: _load),
      );
    }

    final progress = StudentProgressSummary.from(_talents);
    final upcomingMine = upcomingRegistered(_participations, _activities);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildWelcome(),
        const SizedBox(height: AppSpacing.lg),
        _buildKpiRow(progress, upcomingMine.length),
        const SizedBox(height: AppSpacing.lg),
        _buildPanels(progress),
      ],
    );
  }

  /// "สวัสดี, {ชื่อ}" + รหัส/คณะ/ชั้นปี ตาม mockup
  Widget _buildWelcome() {
    final theme = Theme.of(context);
    final code = _profile?.studentId ?? authService.username ?? '-';
    final facts = [
      'รหัส $code',
      if (_profile != null) _profile!.faculty,
      if (_profile != null) 'ชั้นปีที่ ${_profile!.yearLevel}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'สวัสดี, ${_profile?.fullName ?? authService.username ?? ''}',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          facts.join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }

  /// KPI 4 ใบตาม mockup — ไม่มีไอคอน จอแคบยุบ 4 → 2 → 1
  Widget _buildKpiRow(StudentProgressSummary progress, int upcomingCount) {
    final cards = [
      KpiCard(
        label: 'ชั่วโมงสะสม',
        value: '${formatHours(progress.earned)}/${formatHours(progress.required_)}',
        tone: progress.completed ? KpiTone.good : KpiTone.neutral,
      ),
      KpiCard(
        label: 'ครบแล้ว',
        value: '${progress.percent.round()}%',
        tone: progress.completed ? KpiTone.good : KpiTone.neutral,
      ),
      KpiCard(
        label: 'รายการที่ยังไม่ครบ',
        value: '${progress.gaps.length}',
        tone: progress.gaps.isEmpty ? KpiTone.good : KpiTone.warning,
      ),
      KpiCard(
        label: 'กิจกรรมที่กำลังจะถึง',
        value: '$upcomingCount',
        sub: 'ที่คุณสมัครไว้',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 900 => 4,
          >= 560 => 2,
          _ => 1,
        };
        final width = (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }

  /// การ์ดชั่วโมงตาม Talent/PLO (ซ้าย) + แนะนำให้เข้าร่วม (ขวา) ตาม mockup
  Widget _buildPanels(StudentProgressSummary progress) {
    final talents = TalentProgressCard(
      talents: _talents,
      onOpenDetail: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyHoursScreen()),
      ),
    );
    final suggestions = SuggestedActivitiesCard(
      activities: recommendedActivities(
        activities: _activities,
        participations: _participations,
        gapItemIds: progress.gapItemIds,
      ),
      matchedGaps: progress.gaps.isNotEmpty,
      onSeeAll: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ActivitiesScreen()),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [talents, const SizedBox(height: AppSpacing.lg), suggestions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: talents),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: 280, child: suggestions),
          ],
        );
      },
    );
  }
}

/// ทางลัดหน้าแรก — ทุกอันมีเมนูบน sidebar แล้ว (ยกเว้น "กิจกรรม" ที่เมนูใช้ "สมัครกิจกรรม")
/// คงไว้เป็นทางเข้าที่สองสำหรับนิสิตที่คุ้นกับการกดจากหน้าแรก
class _ShortcutSection extends StatelessWidget {
  const _ShortcutSection();

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    final shortcuts = [
      _Shortcut(
        icon: Icons.qr_code_scanner,
        title: 'เช็กอินหน้างาน',
        subtitle: 'สแกน QR ของกิจกรรมเพื่อบันทึกว่ามาร่วมงาน',
        onTap: () => open(const CheckinScanScreen()),
      ),
      _Shortcut(
        icon: Icons.fact_check_outlined,
        title: 'การเข้าร่วมกิจกรรม',
        subtitle: 'ดูประวัติการเข้าร่วมและส่งหลักฐาน',
        onTap: () => open(const ParticipationsScreen()),
      ),
      _Shortcut(
        icon: Icons.event_outlined,
        title: 'กิจกรรม',
        subtitle: 'ดูกิจกรรมทั้งหมด',
        onTap: () => open(const ActivitiesScreen()),
      ),
      _Shortcut(
        icon: Icons.calendar_month_outlined,
        title: 'ปฏิทินกิจกรรม',
        subtitle: 'ดูว่าวันไหนมีกิจกรรมอะไรบ้าง',
        onTap: () => open(const ActivityCalendarScreen()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'ทางลัด'),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = switch (constraints.maxWidth) {
              >= 900 => 4,
              >= 600 => 2,
              _ => 1,
            };
            final width =
                (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final s in shortcuts) SizedBox(width: width, child: s),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.blueBg,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(icon, size: 20, color: AppColors.blue),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
