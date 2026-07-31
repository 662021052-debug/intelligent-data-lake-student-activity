import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/activity.dart';
import '../models/hour_category.dart';
import '../models/participation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_error.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_chip.dart';

const _thaiMonths = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

const _thaiWeekdays = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];

/// "ตุลาคม 2568" — ปีพุทธศักราชตามที่ใช้ทั้งระบบ
String thaiMonthTitle(DateTime day) => '${_thaiMonths[day.month - 1]} ${day.year + 543}';

/// ชื่อวันแบบย่อ (จ. อ. พ. …) — สัปดาห์เริ่มวันจันทร์ตามปฏิทินไทย
String thaiWeekdayLabel(DateTime day) => _thaiWeekdays[day.weekday - 1];

String _twoDigits(int n) => n.toString().padLeft(2, '0');

String _timeRange(Activity a) => '${_twoDigits(a.startAt.hour)}:${_twoDigits(a.startAt.minute)} น.';

String _trimHours(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toString();

/// ปฏิทินกิจกรรม — ดูได้ทั้ง 3 role
///
/// สิทธิ์การมองเห็นเป็นของ backend เหมือนเดิม: ใช้ `GET /activities` ตัวเดียวกับ
/// หน้ารายการ ซึ่งกรองตาม role อยู่แล้ว (นิสิตเห็นเฉพาะ approved, staff เห็นของ
/// ตัวเอง, admin เห็นทั้งหมด) หน้านี้แค่จัดกลุ่มตามวันเท่านั้น
class ActivityCalendarScreen extends StatefulWidget {
  const ActivityCalendarScreen({super.key});

  @override
  State<ActivityCalendarScreen> createState() => _ActivityCalendarScreenState();
}

class _ActivityCalendarScreenState extends State<ActivityCalendarScreen> {
  final Map<DateTime, List<Activity>> _byDay = {};
  List<HourCategory> _categories = [];
  Map<int, Participation> _ownParticipationByActivity = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _format = CalendarFormat.month;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(DateTime.now());
    _load();
  }

  /// ตัดเวลาออกเพื่อใช้เป็นคีย์ของวัน (ไม่งั้นกิจกรรมคนละเวลาจะอยู่คนละกลุ่ม)
  DateTime _dateOnly(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activities = await ApiService.fetchAll('/activities', Activity.fromJson);
      final categories = await ApiService.fetchList('/hour-categories', HourCategory.fromJson);
      // นิสิตต้องเห็นว่าอันไหนสมัครไปแล้ว จะได้ไม่กดซ้ำ
      final participations = authService.role == 'student'
          ? await ApiService.fetchAll('/participations', Participation.fromJson)
          : <Participation>[];

      final grouped = <DateTime, List<Activity>>{};
      for (final a in activities) {
        grouped.putIfAbsent(_dateOnly(a.startAt), () => []).add(a);
      }
      for (final list in grouped.values) {
        list.sort((a, b) => a.startAt.compareTo(b.startAt));
      }

      setState(() {
        _byDay
          ..clear()
          ..addAll(grouped);
        _categories = categories;
        _ownParticipationByActivity = {for (final p in participations) p.activityId: p};
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Activity> _activitiesOn(DateTime day) => _byDay[_dateOnly(day)] ?? const [];

  Future<void> _register(Activity a) async {
    final path = subcategoryPath(_categories, a.subcategoryId);
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการสมัคร',
      message: 'สมัครเข้าร่วม "${a.name}"\n'
          '${_timeRange(a)} • ${a.location}\n\n'
          'ได้ ${_trimHours(a.hours)} ชั่วโมง\n'
          'เข้าหมวด $path',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ปฏิทินกิจกรรม'),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'โหลดใหม่',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    _buildCalendar(),
                    const Divider(height: 1),
                    Expanded(child: _buildDayList()),
                  ],
                ),
    );
  }

  Widget _buildCalendar() {
    final scheme = Theme.of(context).colorScheme;
    return TableCalendar<Activity>(
      // ช่วงกว้างพอให้ดูกิจกรรมย้อนหลังและล่วงหน้าได้ทั้งปีการศึกษา
      firstDay: DateTime.utc(DateTime.now().year - 2, 1, 1),
      lastDay: DateTime.utc(DateTime.now().year + 2, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: _format,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      eventLoader: _activitiesOn,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableCalendarFormats: const {
        CalendarFormat.month: 'เดือน',
        CalendarFormat.twoWeeks: '2 สัปดาห์',
        CalendarFormat.week: 'สัปดาห์',
      },
      // ใช้ตัวจัดรูปแบบภาษาไทยเอง จึงไม่ต้องพึ่ง locale data ของ intl
      headerStyle: HeaderStyle(
        formatButtonShowsNext: false,
        titleCentered: true,
        titleTextFormatter: (day, _) => thaiMonthTitle(day),
        titleTextStyle: Theme.of(context).textTheme.titleMedium ?? const TextStyle(),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        dowTextFormatter: (day, _) => thaiWeekdayLabel(day),
      ),
      calendarStyle: CalendarStyle(
        markerDecoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        todayDecoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(color: scheme.onPrimaryContainer),
        selectedDecoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      ),
      onDaySelected: (selected, focused) {
        setState(() {
          _selectedDay = _dateOnly(selected);
          _focusedDay = focused;
        });
      },
      onFormatChanged: (format) => setState(() => _format = format),
      onPageChanged: (focused) => _focusedDay = focused,
    );
  }

  Widget _buildDayList() {
    final day = _selectedDay ?? _dateOnly(DateTime.now());
    final activities = _activitiesOn(day);
    if (activities.isEmpty) {
      return EmptyState(
        icon: Icons.event_busy_outlined,
        title: 'ไม่มีกิจกรรมวันที่ ${day.day} ${thaiMonthTitle(day)}',
        message: 'เลือกวันอื่นในปฏิทินด้านบน (วันที่มีจุดใต้ตัวเลขคือวันที่มีกิจกรรม)',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: activities.length,
      itemBuilder: (context, index) => _activityCard(activities[index]),
    );
  }

  Widget _activityCard(Activity a) {
    final theme = Theme.of(context);
    final isStudent = authService.role == 'student';
    final participation = _ownParticipationByActivity[a.id];
    final closed = a.startAt.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            _twoDigits(a.startAt.hour),
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        title: Text(a.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_timeRange(a)} • ${a.location}'),
            Text('${a.activityType} • รับ ${a.participantCount}/${a.maxParticipants} คน'),
            Text(
              'ได้ ${_trimHours(a.hours)} ชม. • ${subcategoryPath(_categories, a.subcategoryId)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: isStudent ? _studentAction(a, participation, closed) : _staffStatus(a),
      ),
    );
  }

  /// นิสิต: กดสมัครได้จากปฏิทินเลยถ้ายังเปิดรับ
  Widget _studentAction(Activity a, Participation? participation, bool closed) {
    if (participation != null) {
      return StatusChip.evidence(participation.evidenceStatus, dense: true);
    }
    if (a.isFull) {
      return const StatusChip(
        label: 'เต็มแล้ว',
        palette: StatusPalette.neutral,
        icon: Icons.group_off_outlined,
        dense: true,
      );
    }
    if (closed) {
      return const StatusChip(
        label: 'ผ่านไปแล้ว',
        palette: StatusPalette.neutral,
        icon: Icons.lock_clock,
        dense: true,
      );
    }
    return FilledButton(onPressed: () => _register(a), child: const Text('สมัคร'));
  }

  Widget _staffStatus(Activity a) => StatusChip.activityApproval(a.approvalStatus, dense: true);
}
