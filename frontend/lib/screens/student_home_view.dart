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
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_data_table.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import 'activities_screen.dart';
import 'activity_calendar_screen.dart';
import 'checkin_scan_screen.dart';
import 'my_hours_screen.dart';
import 'participations_screen.dart';

/// หน้าแรกของนิสิตตาม mockup: ข้อมูลส่วนตัว + ชั่วโมงสะสมแยกหมวด ทางซ้าย
/// และประวัติกิจกรรมที่เข้าร่วมทางขวา
///
/// ทุกอย่างมาจาก endpoint ที่มีอยู่แล้ว ไม่ได้เพิ่ม/แก้ API:
/// - `/students/me/hours-summary` ชั่วโมงแยกหมวด
/// - `/participations` รายการที่ตัวเองเข้าร่วม
/// - `/activities` เอาไว้เติมสถานที่/วันที่ให้แต่ละรายการ
/// - `/students/{id}` ชื่อ-คณะ (นิสิตอ่านของตัวเองได้) โดยรู้ id จาก participation
class StudentHomeView extends StatefulWidget {
  const StudentHomeView({super.key});

  @override
  State<StudentHomeView> createState() => _StudentHomeViewState();
}

class _StudentHomeViewState extends State<StudentHomeView> {
  List<HourCategorySummary> _hours = [];
  List<Participation> _participations = [];
  Map<int, Activity> _activityById = {};
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
      final hours = await ApiService.fetchList(
        '/students/me/hours-summary',
        HourCategorySummary.fromJson,
      );
      final participations = await ApiService.fetchAll('/participations', Participation.fromJson);
      final activities = await ApiService.fetchAll('/activities', Activity.fromJson);
      if (!mounted) return;
      final byId = {
        for (final a in activities)
          if (a.id != null) a.id!: a,
      };
      // ล่าสุดขึ้นก่อน — นิสิตสนใจของที่เพิ่งไปมามากกว่าของเมื่อปีที่แล้ว
      // กิจกรรมที่หาไม่เจอ (ถูกซ่อน/ลบ) ให้ไปอยู่ท้ายสุดแทนที่จะทำให้ลำดับพัง
      DateTime startAt(Participation p) =>
          byId[p.activityId]?.startAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      participations.sort((a, b) => startAt(b).compareTo(startAt(a)));
      setState(() {
        _hours = hours;
        _participations = participations;
        _activityById = byId;
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
  /// ยังไม่เคยเข้าร่วมกิจกรรมเลยก็จะไม่มี id ให้ถาม — การ์ดจะโชว์เท่าที่รู้
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
                _buildPanels(),
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

  Widget _buildPanels() {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // จอกว้างวางสองคอลัมน์แบบ mockup จอแคบเรียงลงมาเป็นแถวเดียว
        final wide = constraints.maxWidth >= 860;
        final profile = _ProfilePanel(profile: _profile, hours: _hours);
        final history = _HistoryPanel(
          participations: _participations,
          activityById: _activityById,
          onReload: _load,
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [profile, const SizedBox(height: AppSpacing.lg), history],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 300, child: profile),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: history),
          ],
        );
      },
    );
  }
}

/// การ์ดซ้าย: ข้อมูลส่วนตัว + ชั่วโมงสะสมแยกหมวด
class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.profile, required this.hours});

  final Student? profile;
  final List<HourCategorySummary> hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ข้อมูลส่วนตัว', style: theme.textTheme.titleSmall?.copyWith(fontSize: 14)),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(label: 'รหัสนิสิต', value: profile?.studentId ?? authService.username ?? '-'),
          _InfoRow(label: 'ชื่อ', value: profile?.fullName ?? '-'),
          _InfoRow(label: 'คณะ', value: profile?.faculty ?? '-'),
          if (profile != null) _InfoRow(label: 'ชั้นปี', value: '${profile!.yearLevel}'),
          const SizedBox(height: AppSpacing.md),
          // ยังไม่มีทางออกใบประมวลผลให้นิสิตเอง (รายงานที่มีเป็นของแอดมิน)
          // ระหว่างนี้ปุ่มจึงพาไปหน้าที่ดูชั่วโมงแยกหมวดได้ละเอียดที่สุด
          FilledButton.icon(
            style: AppButtonStyles.dark(context),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('ใบประมวลผลกิจกรรม'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyHoursScreen()),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('ชั่วโมงสะสม', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          if (hours.isEmpty)
            Text(
              'ยังไม่มีชั่วโมงสะสม — ชั่วโมงจะขึ้นเมื่อหลักฐานได้รับการอนุมัติ',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
            )
          else
            for (final c in hours) ...[
              ProgressRow(
                label: c.name,
                value: '${formatHours(c.earnedHours)}/${formatHours(c.requiredHours)}',
                progress: c.requiredHours == 0 ? 1 : c.earnedHours / c.requiredHours,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }
}

/// บรรทัด "ป้ายชื่อ ... ค่า" ของการ์ดข้อมูลส่วนตัว
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.sub)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดขวา: ตารางกิจกรรมที่เข้าร่วม
class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({
    required this.participations,
    required this.activityById,
    required this.onReload,
  });

  final List<Participation> participations;
  final Map<int, Activity> activityById;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(
            title: 'กิจกรรมที่เข้าร่วม',
            subtitle: 'ทั้งหมด ${participations.length} รายการ',
            actions: [
              AppIconButton(
                icon: Icons.refresh,
                tooltip: 'โหลดใหม่',
                onPressed: onReload,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (participations.isEmpty)
            const EmptyState(
              icon: Icons.event_note_outlined,
              title: 'ยังไม่มีกิจกรรมที่เข้าร่วม',
              message: 'เมื่อสมัครและเข้าร่วมกิจกรรม รายการจะแสดงที่นี่',
            )
          else
            AppDataTable(
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('กิจกรรม')),
                DataColumn(label: Text('สถานที่')),
                DataColumn(label: Text('วันที่จัด')),
                DataColumn(label: Text('สถานะ')),
              ],
              rows: [
                for (final (index, p) in participations.indexed)
                  _row(context, index, p, activityById[p.activityId]),
              ],
            ),
        ],
      ),
    );
  }

  List<DataCell> _row(BuildContext context, int index, Participation p, Activity? activity) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.sub);
    return [
      DataCell(Text('${index + 1}', style: muted)),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            p.activityName ?? activity?.name ?? '-',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      DataCell(Text(activity?.location ?? '-', style: muted)),
      DataCell(Text(activity == null ? '-' : formatThaiDate(activity.startAt), style: muted)),
      DataCell(StatusChip.evidence(p.evidenceStatus, dense: true)),
    ];
  }
}

/// ทางลัดไปหน้าที่ไม่ได้อยู่บนแถบเมนูด้านบน (เมนูบนจำกัดไว้ 4 ช่องตาม mockup)
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
