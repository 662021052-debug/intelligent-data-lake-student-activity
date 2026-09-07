import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/hour_category.dart';
import '../models/hour_summary.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/search_field.dart';
import '../widgets/status_chip.dart';
import 'app_shell.dart';
// ใช้กฎ "วันไหนถือว่าผ่านไปแล้ว" ร่วมกับหน้าจัดการกิจกรรม จะได้มีนิยามเดียว —
// ไม่งั้นสองหน้าอาจตัดวันคนละเวลาแล้วนิสิตเห็นรายการไม่ตรงกัน
import 'activities_screen.dart' show activityFirstSelectableDate, isBackdatedActivity;

/// กิจกรรมนี้ยังไม่ผ่านวันจัดใช่ไหม (เทียบระดับวัน เหมือนกฎฝั่ง backend)
bool isUpcomingActivity(Activity a, [DateTime? now]) =>
    !isBackdatedActivity(a.startAt, now);

/// ลำดับที่นิสิตควรเห็น: อันที่ใกล้ที่สุดก่อน แล้วค่อยตามด้วยอันที่จัดไปแล้ว
/// (เพิ่งจบก่อน) — เรียงตามวันเฉย ๆ จะทำให้กิจกรรมที่จบไปแล้วมากองบังของที่ยัง
/// สมัครทันอยู่ด้านบน
List<Activity> sortActivitiesForStudent(List<Activity> activities, [DateTime? now]) {
  final upcoming = <Activity>[];
  final past = <Activity>[];
  for (final a in activities) {
    (isUpcomingActivity(a, now) ? upcoming : past).add(a);
  }
  upcoming.sort((a, b) => a.startAt.compareTo(b.startAt));
  past.sort((a, b) => b.startAt.compareTo(a.startAt));
  return [...upcoming, ...past];
}

/// ป้ายบอกว่าเหลืออีกกี่วัน — ช่วยให้นิสิตกะได้ว่าต้องรีบสมัครแค่ไหน
String countdownLabel(DateTime startAt, [DateTime? now]) {
  final today = activityFirstSelectableDate(now);
  final day = DateTime(startAt.year, startAt.month, startAt.day);
  final days = day.difference(today).inDays;
  if (days < 0) return 'จัดไปแล้ว';
  if (days == 0) return 'วันนี้';
  if (days == 1) return 'พรุ่งนี้';
  return 'อีก $days วัน';
}

/// ที่นั่ง: บอกทั้งจำนวนที่รับและที่ยังเหลือ เพราะ "20/50" อย่างเดียวยังต้องคิดต่อ
String seatsLabel(Activity a) {
  final remaining = a.maxParticipants - a.participantCount;
  if (remaining <= 0) return 'เต็มแล้ว (รับ ${a.maxParticipants} คน)';
  return 'สมัครแล้ว ${a.participantCount}/${a.maxParticipants} คน • เหลือ $remaining ที่';
}

class RegisterActivitiesScreen extends StatefulWidget {
  const RegisterActivitiesScreen({super.key});

  @override
  State<RegisterActivitiesScreen> createState() => _RegisterActivitiesScreenState();
}

class _RegisterActivitiesScreenState extends State<RegisterActivitiesScreen> {
  List<Activity> _activities = [];
  List<HourCategory> _categories = [];
  List<HourCategorySummary> _myHours = [];
  Map<int, Participation> _ownParticipationByActivity = {};
  bool _loading = false;
  String? _error;
  String _search = '';

  /// ค่าเริ่มต้นแสดงเฉพาะกิจกรรมที่ยังไม่ถึงวันจัด — เปิดอันนี้เพื่อดูย้อนหลัง
  bool _includePast = false;

  /// กิจกรรมที่ผ่านช่องค้นหา — กรองในเครื่องเพราะโหลดรายการมาครบแล้ว
  List<Activity> get _visible {
    if (_search.isEmpty) return _activities;
    final needle = _search.toLowerCase();
    return _activities.where((a) {
      final haystack = '${a.name} ${a.activityType} ${a.location} '
              '${subcategoryPath(_categories, a.subcategoryId)}'
          .toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

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
      // นิสิตต้องเห็นรายการทันทีที่เข้าหน้า โดยไม่ต้องกดค้นหา/กรองก่อน — ค่าเริ่มต้น
      // จึงขอเฉพาะกิจกรรมที่ยังไม่ผ่านวันจัด (backend กรอง approved ให้อยู่แล้ว)
      final activities = await ApiService.fetchAll(
        '/activities',
        Activity.fromJson,
        query: _includePast ? null : {'upcoming': 'true'},
      );
      final participations = await ApiService.fetchAll('/participations', Participation.fromJson);
      // ชื่อหมวดชั่วโมง + ชั่วโมงสะสมของตัวเอง ใช้บอกว่า "สมัครแล้วได้อะไร เข้าหมวดที่ยังขาดไหม"
      final categories = await ApiService.fetchList('/hour-categories', HourCategory.fromJson);
      final myHours = await ApiService.fetchList(
        '/students/me/hours-summary',
        HourCategorySummary.fromJson,
      );
      setState(() {
        _activities = sortActivitiesForStudent(activities);
        _categories = categories;
        _myHours = myHours;
        _ownParticipationByActivity = {
          for (final p in participations) p.activityId: p,
        };
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// สรุปสถานะหมวดของกิจกรรมนี้เทียบกับชั่วโมงที่นิสิตมีอยู่ (null ถ้าไม่รู้จักหมวด)
  String? _categoryProgress(Activity a) {
    final parent = parentCategoryOf(_categories, a.subcategoryId);
    if (parent == null) return null;
    for (final summary in _myHours) {
      if (summary.id != parent.id) continue;
      if (summary.completed) {
        return 'หมวดนี้คุณครบแล้ว (${formatHours(summary.earnedHours)}/'
            '${formatHours(summary.requiredHours)} ชม.)';
      }
      final remaining = summary.requiredHours - summary.earnedHours;
      return 'หมวดนี้คุณมี ${formatHours(summary.earnedHours)}/'
          '${formatHours(summary.requiredHours)} ชม. — ยังขาดอีก ${formatHours(remaining)} ชม.';
    }
    return null;
  }

  Future<void> _register(Activity a) async {
    final categoryPath = subcategoryPath(_categories, a.subcategoryId);
    final progress = _categoryProgress(a);
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการสมัคร',
      message: 'สมัครเข้าร่วม "${a.name}"\n'
          'วันเวลา ${formatThaiDateTime(a.startAt)} • ${a.location}\n\n'
          'ได้ ${formatHours(a.hours)} ชั่วโมง\n'
          'เข้าหมวด $categoryPath',
      detail: [
        'ชั่วโมงจะถูกนับเมื่อหลักฐานผ่านการอนุมัติ',
        ?progress,
      ].join('\n'),
      confirmLabel: 'สมัคร',
      icon: Icons.how_to_reg,
    );
    if (confirmed != true) return;
    try {
      await ApiService.create(
        '/participations/register',
        {'activity_id': a.id},
        Participation.fromJson,
      );
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _cancel(Participation p, Activity a) async {
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการยกเลิก',
      message: 'ยกเลิกการสมัคร "${a.name}"',
      detail: 'รายการนี้จะถูกลบออกจากประวัติการเข้าร่วม ถ้าเปลี่ยนใจต้องสมัครใหม่',
      confirmLabel: 'ยกเลิกการสมัคร',
      icon: Icons.cancel_outlined,
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await ApiService.delete('/participations/${p.id}');
      _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      activeId: 'register',
      // แถบค้นหา/กรองอยู่นอกส่วนที่สลับไปมา เพื่อให้กดสลับ "รวมที่จัดไปแล้ว" ได้
      // แม้ตอนนั้นจะยังไม่มีกิจกรรมที่กำลังจะถึงให้แสดง
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
                    SectionHeader(
                      title: 'สมัครกิจกรรม',
                      subtitle: 'กิจกรรมที่เปิดรับสมัคร ${_visible.length} รายการ',
                      actions: [
                        AppIconButton(
                          icon: Icons.refresh,
                          tooltip: 'โหลดใหม่',
                          onPressed: _load,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DebouncedSearchField(
                          label: 'ค้นหากิจกรรม/หมวด/สถานที่',
                          width: 340,
                          onSearch: (value) => setState(() => _search = value),
                        ),
                        FilterChip(
                          label: const Text('รวมกิจกรรมที่จัดไปแล้ว'),
                          selected: _includePast,
                          onSelected: (value) {
                            setState(() => _includePast = value);
                            _load();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingState(message: 'กำลังโหลดกิจกรรม...');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_activities.isEmpty) return _emptyState();
    final visible = _visible;
    if (visible.isEmpty) return EmptyState.noResults();

    // การ์ดเรียงเป็นตารางแบบ mockup: จอกว้างสองใบต่อแถว จอแคบใบเดียวเต็มความกว้าง
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        final width = (constraints.maxWidth - 40 - AppSpacing.lg * (columns - 1)) / columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            children: [
              for (final a in visible) SizedBox(width: width, child: _activityCard(a)),
            ],
          ),
        );
      },
    );
  }

  /// ไม่มีรายการเลย: แยก "ยังไม่มีอันที่กำลังจะถึง" ออกจาก "ไม่มีกิจกรรมในระบบ"
  /// เพราะทางแก้ของนิสิตต่างกัน (รอ vs เปิดดูย้อนหลัง)
  Widget _emptyState() => EmptyState(
        icon: Icons.event_available_outlined,
        title: _includePast ? 'ยังไม่มีกิจกรรมในระบบ' : 'ยังไม่มีกิจกรรมที่กำลังจะถึง',
        message: _includePast
            ? 'เมื่อเจ้าหน้าที่เพิ่มและอนุมัติกิจกรรม รายการจะแสดงที่นี่'
            : 'กิจกรรมที่เปิดรับสมัครจะขึ้นที่นี่เองโดยไม่ต้องกดค้นหา '
                'ระหว่างนี้เปิด "รวมกิจกรรมที่จัดไปแล้ว" เพื่อดูย้อนหลังได้',
      );

  Widget _activityCard(Activity a) {
    final theme = Theme.of(context);
    final participation = _ownParticipationByActivity[a.id];
    final closed = a.startAt.isBefore(DateTime.now());

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              StatusChip(label: a.activityType, palette: StatusPalette.neutral, dense: true),
              StatusChip(
                label: countdownLabel(a.startAt),
                palette: closed ? StatusPalette.neutral : StatusPalette.info,
                dense: true,
              ),
              if (a.isRequired)
                const StatusChip(
                  label: 'กิจกรรมบังคับ',
                  palette: StatusPalette.pending,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(a.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          // นิสิตต้องรู้ก่อนกดสมัครว่าได้กี่ชั่วโมงและเข้าหมวดไหน
          Text(
            subcategoryPath(_categories, a.subcategoryId),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              MetaItem(icon: Icons.schedule, label: 'ได้ ${formatHours(a.hours)} ชม.'),
              MetaItem(icon: Icons.event, label: formatThaiDateTime(a.startAt)),
              MetaItem(icon: Icons.place_outlined, label: a.location),
              MetaItem(icon: Icons.groups_outlined, label: seatsLabel(a)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildAction(a, participation, closed),
        ],
      ),
    );
  }

  /// ปุ่ม/สถานะท้ายการ์ด — สมัครได้ / สมัครแล้ว / เต็ม / ปิดรับ
  Widget _buildAction(Activity a, Participation? participation, bool closed) {
    if (participation != null) {
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusChip.evidence(participation.evidenceStatus, dense: true),
          OutlinedButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: const Text('ยกเลิกการสมัคร'),
            style: AppButtonStyles.danger(context),
            onPressed: () => _cancel(participation, a),
          ),
        ],
      );
    }
    if (a.isFull) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'เต็มแล้ว',
          palette: StatusPalette.neutral,
          icon: Icons.group_off_outlined,
          dense: true,
        ),
      );
    }
    if (closed) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(
          label: 'ปิดรับสมัครแล้ว',
          palette: StatusPalette.neutral,
          icon: Icons.lock_clock,
          dense: true,
        ),
      );
    }
    return FilledButton(
      onPressed: () => _register(a),
      child: const Text('สมัครเข้าร่วม'),
    );
  }
}
