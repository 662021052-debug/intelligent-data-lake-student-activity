import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../models/criteria_set.dart';
import '../models/hour_category.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';
import 'activities_screen.dart';
import 'activity_participants_screen.dart';
import 'app_shell.dart';

const _thaiMonths = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

const _thaiWeekdays = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
const _thaiWeekdaysFull = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

/// กว้างกว่านี้วางปฏิทิน + แผงวันเคียงกัน แคบกว่านี้ซ้อนเป็นคอลัมน์เดียว
const double kCalendarWideBreakpoint = 980;

/// ความกว้างแผงรายละเอียดวันทางขวา (ตาม mockup v2)
const double kCalendarDayPanelWidth = 348;

/// ความสูงขั้นต่ำของช่องวัน — พอสำหรับเลขวัน + ชิป 2 อัน + "+N เพิ่ม"
/// (ช่องยืดเองถ้าตัวอักษรใหญ่กว่านี้ ไม่ตัดจนล้น)
const double kCalendarCellMinHeight = 96;

/// ช่องที่แคบกว่านี้อ่านชื่อกิจกรรมไม่ออกแล้ว — เปลี่ยนเป็นแถบสีแทนชิปชื่อ
const double kCalendarCompactCellWidth = 72;

/// ชิปชื่อกิจกรรมสูงสุดต่อช่องวัน ที่เกินรวมเป็น "+N เพิ่ม"
const int kCalendarMaxChips = 2;

/// "ตุลาคม 2568" — ปีพุทธศักราชตามที่ใช้ทั้งระบบ
String thaiMonthTitle(DateTime day) => '${_thaiMonths[day.month - 1]} ${day.year + 543}';

/// ชื่อวันแบบย่อ (จ. อ. พ. …) — สัปดาห์เริ่มวันจันทร์ตามปฏิทินไทย
String thaiWeekdayLabel(DateTime day) => _thaiWeekdays[day.weekday - 1];

/// "วันจันทร์ที่ 14 กันยายน 2569" — หัวแผงรายละเอียดวัน
String thaiFullDateLabel(DateTime day) =>
    'วัน${_thaiWeekdaysFull[day.weekday - 1]}ที่ ${day.day} ${_thaiMonths[day.month - 1]} ${day.year + 543}';

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _clock(DateTime dt) => '${_twoDigits(dt.hour)}:${_twoDigits(dt.minute)}';

/// "09:00–12:00 น." — เวลาจบคิดจากชั่วโมงของกิจกรรม (ไม่มีช่องเวลาจบในข้อมูล)
///
/// `start_at` เป็นเวลาไทยแบบไม่มีโซนอยู่แล้ว (ดู backend/app/timeutil.py) จึงใช้ตรง ๆ
/// ห้ามส่งผ่าน `serverTimeToLocal()` ซึ่งมีไว้สำหรับ timestamp จาก `utcnow()` เท่านั้น
/// ไม่งั้นทุกกิจกรรมจะเลื่อนไป 7 ชม.
String activityTimeRange(Activity a) {
  final minutes = (a.hours * 60).round();
  if (minutes <= 0) return '${_clock(a.startAt)} น.';
  return '${_clock(a.startAt)}–${_clock(a.startAt.add(Duration(minutes: minutes)))} น.';
}

/// ที่นั่งที่ยังว่าง (ไม่ติดลบแม้ข้อมูลเก่าจะรับเกินความจุ)
int activitySeatsLeft(Activity a) => math.max(0, a.maxParticipants - a.participantCount);

/// "เหลือ 9 / 10" หรือ "เต็มแล้ว 15 / 15"
String activitySeatsLabel(Activity a) => a.isFull
    ? 'เต็มแล้ว ${a.participantCount} / ${a.maxParticipants}'
    : 'เหลือ ${activitySeatsLeft(a)} / ${a.maxParticipants}';

/// สีของชิปกิจกรรมบนปฏิทิน ตาม role ของคนที่ดู
///
/// - นิสิตเห็นแต่กิจกรรมที่อนุมัติแล้ว สี "อนุมัติ" จึงไม่บอกอะไร — ใช้ เขียว = สมัครแล้ว,
///   ฟ้า = ยังไม่ได้สมัคร (ตรงกับ badge "สมัครแล้ว" ในแผงวัน)
/// - staff/admin: เขียว = อนุมัติแล้ว, เหลือง = รออนุมัติ, เทา = ซ่อนอยู่
StatusPalette calendarChipPalette(
  Activity a, {
  required bool isStudent,
  bool registered = false,
}) {
  if (isStudent) return registered ? StatusPalette.approved : StatusPalette.info;
  if (a.isHidden) return StatusPalette.neutral;
  return a.approvalStatus == 'approved' ? StatusPalette.approved : StatusPalette.pending;
}

/// ตัดเวลาออกเพื่อใช้เป็นคีย์ของวัน (ไม่งั้นกิจกรรมคนละเวลาจะอยู่คนละกลุ่ม)
DateTime activityDayKey(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "2026-09-14" — ใช้ประกอบ key ของช่องวัน (เทสต์/E2E หาช่องวันได้ตรงตัว)
String calendarDayId(DateTime day) =>
    '${day.year}-${_twoDigits(day.month)}-${_twoDigits(day.day)}';

/// วันที่ทั้งหมดที่ตารางเดือนต้องวาด — เริ่มวันจันทร์ จบวันอาทิตย์ เต็มสัปดาห์เสมอ
///
/// รวมวันท้ายเดือนก่อน/ต้นเดือนถัดไปที่ตกอยู่ในสัปดาห์เดียวกัน (วาดจาง ๆ)
/// ความยาวจึงเป็น 28 / 35 / 42 วัน
List<DateTime> calendarMonthDays(DateTime month) {
  final first = DateTime.utc(month.year, month.month, 1);
  final last = DateTime.utc(month.year, month.month + 1, 0);
  final start = first.subtract(Duration(days: first.weekday - DateTime.monday));
  final total = (last.difference(start).inDays + 1) + (DateTime.sunday - last.weekday);
  return [for (var i = 0; i < total; i++) DateTime.utc(start.year, start.month, start.day + i)];
}

/// จัดกิจกรรมเข้ากลุ่มตามวันที่จัด เรียงตามเวลาเริ่มภายในแต่ละวัน
///
/// เป็นฟังก์ชันบริสุทธิ์เพื่อให้เทสต์ยืนยันการจัดกลุ่มได้โดยไม่ต้องมีฐานข้อมูล —
/// ชิปในช่องวันและรายการในแผงวันอ่านจากผลของฟังก์ชันนี้ตัวเดียวกัน
Map<DateTime, List<Activity>> groupActivitiesByDay(List<Activity> activities) {
  final grouped = <DateTime, List<Activity>>{};
  for (final a in activities) {
    grouped.putIfAbsent(activityDayKey(a.startAt), () => []).add(a);
  }
  for (final list in grouped.values) {
    list.sort((a, b) => a.startAt.compareTo(b.startAt));
  }
  return grouped;
}

/// ปฏิทินกิจกรรม — ตัวเดียวใช้ทั้ง 3 role
///
/// ปฏิทินซ้าย + แผงรายละเอียดวันขวา (จอแคบซ้อนเป็นคอลัมน์เดียว) โครงเหมือนกันทุก role
/// ต่างกันแค่สีชิป, badge และปุ่มในการ์ดกิจกรรม
///
/// สิทธิ์การมองเห็นเป็นของ backend เหมือนเดิม: ใช้ `GET /activities` ตัวเดียวกับหน้า
/// รายการ ซึ่งกรองตาม role อยู่แล้ว (นิสิตเห็นเฉพาะ approved, staff เห็นของตัวเอง,
/// admin เห็นทั้งหมด)
class ActivityCalendarScreen extends StatefulWidget {
  const ActivityCalendarScreen({
    super.key,
    this.initialActivities,
    this.initialParticipations,
  });

  /// กิจกรรมตั้งต้นแทนการเรียก API — **สำหรับเทสต์เท่านั้น**
  ///
  /// หน้านี้ยิง API ตอนเปิด ซึ่งในเทสต์ล้มเสมอ (ApiService เรียก `http.get` ตรง
  /// จึงไม่มีจุดสวม mock client) ช่องทางนี้ให้เทสต์ยืนยันพฤติกรรมจริงของหน้าได้
  @visibleForTesting
  final List<Activity>? initialActivities;

  /// การเข้าร่วมของนิสิตที่ล็อกอินอยู่ ใช้คู่กับ [initialActivities] — **สำหรับเทสต์เท่านั้น**
  @visibleForTesting
  final List<Participation>? initialParticipations;

  @override
  State<ActivityCalendarScreen> createState() => _ActivityCalendarScreenState();
}

class _ActivityCalendarScreenState extends State<ActivityCalendarScreen> {
  final Map<DateTime, List<Activity>> _byDay = {};
  List<HourCategory> _categories = [];
  List<CriteriaSet> _criteriaSets = [];
  Map<int, Participation> _ownParticipationByActivity = {};
  late DateTime _month;
  late DateTime _selectedDay;
  bool _loading = false;
  String? _error;

  DateTime get _today => activityDayKey(DateTime.now());
  bool get _isStudent => authService.role == 'student';

  @override
  void initState() {
    super.initState();
    _selectedDay = _today;
    _month = DateTime.utc(_today.year, _today.month);
    final seeded = widget.initialActivities;
    if (seeded != null) {
      _byDay.addAll(groupActivitiesByDay(seeded));
      _ownParticipationByActivity = {
        for (final p in widget.initialParticipations ?? const <Participation>[]) p.activityId: p,
      };
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activities = await ApiService.fetchAll('/activities', Activity.fromJson);
      final categories = await ApiService.fetchList('/hour-categories', HourCategory.fromJson);
      // นิสิตต้องเห็นว่าอันไหนสมัครไปแล้ว จะได้ไม่กดซ้ำ
      final participations = _isStudent
          ? await ApiService.fetchAll('/participations', Participation.fromJson)
          : <Participation>[];
      // รายการเกณฑ์ใช้ทั้งบรรทัด "นับเข้าหมวด" ในการ์ด และฟอร์มแก้ไข — เป็นข้อมูลเสริม
      // โหลดไม่ได้ก็ยังเปิดปฏิทินได้ (บรรทัดหมวดจะตกกลับไปใช้หมวดย่อยเดิม)
      List<CriteriaSet> criteriaSets = const [];
      try {
        criteriaSets = await ApiService.fetchList('/criteria-sets', CriteriaSet.fromJson);
      } catch (_) {}

      setState(() {
        _byDay
          ..clear()
          ..addAll(groupActivitiesByDay(activities));
        _categories = categories;
        _criteriaSets = criteriaSets;
        _ownParticipationByActivity = {for (final p in participations) p.activityId: p};
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Activity> _activitiesOn(DateTime day) => _byDay[activityDayKey(day)] ?? const [];

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = activityDayKey(day);
      // กดวันจาง ๆ ของเดือนข้างเคียง = ไปเดือนนั้นเลย
      if (day.month != _month.month || day.year != _month.year) {
        _month = DateTime.utc(day.year, day.month);
      }
    });
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime.utc(_month.year, _month.month + delta));

  void _goToday() => setState(() {
        _selectedDay = _today;
        _month = DateTime.utc(_today.year, _today.month);
      });

  Future<void> _register(Activity a) async {
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการสมัคร',
      message: 'สมัครเข้าร่วม "${a.name}"\n'
          '${activityTimeRange(a)} • ${a.location}\n\n'
          'ได้ ${formatHours(a.hours)} ชั่วโมง\n'
          'นับเข้าหมวด ${activityCriteriaLabel(_categories, _criteriaSets, a)}',
      detail: 'ชั่วโมงจะถูกนับเมื่อหลักฐานผ่านการอนุมัติ',
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
      if (mounted) showInfoSnackbar(context, 'สมัคร "${a.name}" เรียบร้อยแล้ว');
      await _load();
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  /// เปิดหน้าผู้เข้าร่วมของกิจกรรมนั้น — ทางเดียวกับที่หน้าจัดการกิจกรรมใช้
  void _openParticipants(Activity a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActivityParticipantsScreen(activity: a)),
    );
  }

  /// แก้กิจกรรมจากปฏิทินได้เลย ไม่ต้องจำชื่อแล้วไปหาในหน้ารายการอีกรอบ
  Future<void> _edit(Activity a) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ActivityFormDialog(
        existing: a,
        categories: _categories,
        criteriaSets: _criteriaSets,
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      activeId: 'calendar',
      title: 'ปฏิทินกิจกรรม',
      subtitle: 'กดที่วันเพื่อดูรายละเอียดกิจกรรมของวันนั้น',
      filters: [
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: _load),
      ],
      child: _loading
          ? const LoadingState(message: 'กำลังโหลดปฏิทิน...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= kCalendarWideBreakpoint) {
                      // สองคอลัมน์เลื่อนแยกกัน แผงวันจึงค้างอยู่ข้างปฏิทินเสมอ (sticky)
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: SingleChildScrollView(child: _buildCalendarCard())),
                          const SizedBox(width: AppSpacing.lg),
                          SizedBox(
                            width: kCalendarDayPanelWidth,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                              child: _buildDayPanel(scrollable: true),
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView(
                      children: [
                        _buildCalendarCard(),
                        const SizedBox(height: AppSpacing.lg),
                        _buildDayPanel(scrollable: false),
                      ],
                    );
                  },
                ),
    );
  }

  // --------------------------- ปฏิทิน ---------------------------

  Widget _buildCalendarCard() {
    return AppCard(
      key: const ValueKey('calendar-month'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1),
          _buildWeekdayRow(),
          const Divider(height: 1),
          _buildGrid(),
        ],
      ),
    );
  }

  ButtonStyle get _headerButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: AppColors.blueDark,
        side: const BorderSide(color: AppColors.line),
        minimumSize: const Size(34, 34),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  Widget _navButton(IconData icon, String tooltip, VoidCallback onPressed) => Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 34,
          height: 34,
          child: OutlinedButton(
            onPressed: onPressed,
            style: _headerButtonStyle.copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.zero)),
            child: Icon(icon, size: 20, semanticLabel: tooltip),
          ),
        ),
      );

  Widget _buildHeader() {
    final title = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // จอแคบซ่อนป้ายมุมมอง ให้ชื่อเดือนมีที่พอ
          final showViewLabel = constraints.maxWidth >= 420;
          return Row(
            children: [
              _navButton(Icons.chevron_left, 'เดือนก่อนหน้า', () => _shiftMonth(-1)),
              const SizedBox(width: 6),
              _navButton(Icons.chevron_right, 'เดือนถัดไป', () => _shiftMonth(1)),
              const SizedBox(width: 6),
              OutlinedButton(onPressed: _goToday, style: _headerButtonStyle, child: const Text('วันนี้')),
              Expanded(
                child: Text(
                  thaiMonthTitle(_month),
                  key: const ValueKey('calendar-month-title'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: title,
                ),
              ),
              if (showViewLabel) _viewLabel() else const SizedBox(width: 34),
            ],
          );
        },
      ),
    );
  }

  /// ป้ายมุมมองที่เปิดอยู่ — ตอนนี้มีมุมมองเดียว (รายเดือน) จึงไม่ทำเป็นปุ่มที่กดแล้วไม่มีอะไรเกิดขึ้น
  Widget _viewLabel() => Semantics(
        label: 'มุมมองรายเดือน',
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.blueBg,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: const Text(
            'เดือน',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.blueDark),
          ),
        ),
      );

  Widget _buildWeekdayRow() => Container(
        color: AppColors.fieldFill,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  _thaiWeekdays[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: i >= 5 ? AppColors.muted : AppColors.sub,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth / 7 < kCalendarCompactCellWidth;
        final days = calendarMonthDays(_month);
        return Column(
          children: [
            for (var week = 0; week < days.length; week += 7)
              // แถวสูงเท่าช่องที่สูงที่สุดของสัปดาห์ — กริดตรงกันทั้งแถว ไม่มีช่องไหนล้น
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: _dayCell(
                          days[week + i],
                          lastColumn: i == 6,
                          lastRow: week + 7 >= days.length,
                          compact: compact,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _dayCell(
    DateTime day, {
    required bool lastColumn,
    required bool lastRow,
    required bool compact,
  }) {
    final inMonth = day.month == _month.month;
    final isToday = _sameDay(day, _today);
    final selected = _sameDay(day, _selectedDay);
    final weekend = day.weekday >= DateTime.saturday;
    final activities = _activitiesOn(day);
    const grid = BorderSide(color: AppColors.line);

    return Semantics(
      button: true,
      selected: selected,
      label: '${thaiFullDateLabel(day)} ${activities.isEmpty ? 'ไม่มีกิจกรรม' : 'มี ${activities.length} กิจกรรม'}',
      child: Material(
        color: selected ? AppColors.blueBg : (inMonth ? AppColors.surface : AppColors.fieldFill),
        child: InkWell(
          key: ValueKey('calendar-day-${calendarDayId(day)}'),
          onTap: () => _selectDay(day),
          hoverColor: AppColors.blueBg.withValues(alpha: 0.5),
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 64 : kCalendarCellMinHeight),
            decoration: BoxDecoration(
              border: Border(
                right: lastColumn ? BorderSide.none : grid,
                bottom: lastRow ? BorderSide.none : grid,
              ),
            ),
            padding: EdgeInsets.fromLTRB(compact ? 3 : 7, 6, compact ? 3 : 7, 6),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dayNumber(day,
                      isToday: isToday, selected: selected, inMonth: inMonth, weekend: weekend, compact: compact),
                  if (activities.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    compact ? _compactMarkers(activities) : _chips(activities),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dayNumber(
    DateTime day, {
    required bool isToday,
    required bool selected,
    required bool inMonth,
    required bool weekend,
    required bool compact,
  }) {
    final size = compact ? 22.0 : 26.0;
    final color = isToday
        ? Theme.of(context).colorScheme.onPrimary
        : !inMonth
            ? AppColors.muted
            : weekend
                ? AppColors.sub
                : AppColors.ink;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isToday ? AppColors.blue : null,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: selected && !isToday ? Border.all(color: AppColors.blue, width: 2) : null,
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: compact ? 12 : 13,
          fontWeight: inMonth ? FontWeight.w600 : FontWeight.w400,
          color: color,
        ),
      ),
    );
  }

  StatusPalette _paletteFor(Activity a) => calendarChipPalette(
        a,
        isStudent: _isStudent,
        registered: _ownParticipationByActivity.containsKey(a.id),
      );

  Widget _chips(List<Activity> activities) {
    final extra = activities.length - kCalendarMaxChips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in activities.take(kCalendarMaxChips))
          Padding(padding: const EdgeInsets.only(bottom: 3), child: _chip(a)),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Text(
              '+$extra เพิ่ม',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.blue),
            ),
          ),
      ],
    );
  }

  Widget _chip(Activity a) {
    final palette = _paletteFor(a);
    return Tooltip(
      message: '${a.name}\n${activityTimeRange(a)} • ${a.location}',
      waitDuration: const Duration(milliseconds: 400),
      // ขอบซ้ายสีเดียวกับมุมโค้งใช้คู่กันใน BoxDecoration ไม่ได้ (ต้องขอบเท่ากันทุกด้าน)
      // จึงตัดมุมด้วย ClipRRect แทน
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
          decoration: BoxDecoration(
            color: palette.background,
            border: Border(left: BorderSide(color: palette.accent, width: 3)),
          ),
          child: Text(
            a.name,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: palette.foreground,
            ),
          ),
        ),
      ),
    );
  }

  /// ช่องแคบ (มือถือ) อ่านชื่อไม่ออก — แถบสีตามสถานะสูงสุด 3 แถบ + ตัวเลขที่เหลือ
  Widget _compactMarkers(List<Activity> activities) {
    const maxBars = 3;
    final extra = activities.length - maxBars;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in activities.take(maxBars))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: _paletteFor(a).accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        if (extra > 0)
          Text(
            '+$extra',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.blue),
          ),
      ],
    );
  }

  // --------------------------- แผงรายละเอียดวัน ---------------------------

  Widget _buildDayPanel({required bool scrollable}) {
    final theme = Theme.of(context);
    final activities = _activitiesOn(_selectedDay);
    const bodyPadding = EdgeInsets.fromLTRB(AppSpacing.md + 2, AppSpacing.md + 2, AppSpacing.md + 2, 2);

    final items = activities.isEmpty
        ? <Widget>[_emptyDay()]
        : <Widget>[
            for (final a in activities)
              Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _activityCard(a)),
          ];

    return AppCard(
      key: const ValueKey('calendar-day-panel'),
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md + 2, AppSpacing.lg, AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thaiFullDateLabel(_selectedDay),
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  activities.isEmpty ? 'ไม่มีกิจกรรม' : 'มี ${activities.length} กิจกรรม',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (scrollable)
            Flexible(child: ListView(shrinkWrap: true, padding: bodyPadding, children: items))
          else
            Padding(
              padding: bodyPadding,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
            ),
        ],
      ),
    );
  }

  Widget _emptyDay() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 36, horizontal: AppSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.event_available_outlined, color: AppColors.muted, size: 32),
            SizedBox(height: AppSpacing.sm),
            Text(
              'ไม่มีกิจกรรมในวันนี้',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        ),
      );

  Widget _activityCard(Activity a) {
    const meta = TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.muted);
    final actions = _cardActions(a);
    final seatsColor =
        a.isFull ? StatusPalette.rejected.foreground : StatusPalette.approved.foreground;

    return Container(
      key: ValueKey('calendar-activity-${a.id}'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md + 1, AppSpacing.md, AppSpacing.md + 1, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppRadius.card - 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  a.name,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _cardBadge(a),
            ],
          ),
          const SizedBox(height: 3),
          Text('${activityTimeRange(a)} • ${a.location}', style: meta),
          Text(a.activityType, style: meta),
          const SizedBox(height: 6),
          Text(
            'ได้ ${formatHours(a.hours)} ชม. • ${activityCriteriaLabel(_categories, _criteriaSets, a)}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.blueDark),
          ),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(
              text: 'ที่นั่ง: ',
              children: [
                TextSpan(text: activitySeatsLabel(a), style: TextStyle(color: seatsColor)),
              ],
            ),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.sub),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md - 1),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
          ],
        ],
      ),
    );
  }

  Widget _cardBadge(Activity a) {
    if (_isStudent) {
      return _ownParticipationByActivity.containsKey(a.id)
          ? const StatusChip(
              label: 'สมัครแล้ว',
              palette: StatusPalette.info,
              icon: Icons.how_to_reg_outlined,
              dense: true,
            )
          : const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        StatusChip.activityApproval(a.approvalStatus, dense: true),
        if (a.isHidden) ...[
          const SizedBox(height: AppSpacing.xs),
          const StatusChip(
            label: 'ซ่อนอยู่',
            palette: StatusPalette.neutral,
            icon: Icons.visibility_off_outlined,
            dense: true,
          ),
        ],
      ],
    );
  }

  ButtonStyle get _cardButtonStyle => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.md + 2)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.field)),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  /// ปุ่มในการ์ดตาม role — งานนี้คงพฤติกรรมเดิมไว้ (สมัคร / ดูผู้เข้าร่วม / แก้ไข)
  /// ยกเลิกการสมัคร เตือนเวลาชน และอื่น ๆ เป็นของงานที่ 2
  List<Widget> _cardActions(Activity a) {
    if (_isStudent) {
      if (_ownParticipationByActivity.containsKey(a.id)) return const [];
      final (label, onPressed) = a.isFull
          ? ('เต็มแล้ว', null)
          : a.startAt.isBefore(DateTime.now())
              ? ('ปิดรับสมัครแล้ว', null)
              : ('สมัครเข้าร่วม', () => _register(a));
      return [
        FilledButton.icon(
          onPressed: onPressed,
          style: _cardButtonStyle,
          icon: Icon(onPressed == null ? Icons.block : Icons.add, size: 16),
          label: Text(label),
        ),
      ];
    }
    if (!authService.canWrite) return const [];
    return [
      OutlinedButton.icon(
        onPressed: () => _openParticipants(a),
        style: _cardButtonStyle,
        icon: const Icon(Icons.groups_outlined, size: 16),
        label: const Text('ผู้เข้าร่วม'),
      ),
      OutlinedButton.icon(
        onPressed: () => _edit(a),
        style: _cardButtonStyle,
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('แก้ไข'),
      ),
    ];
  }
}
