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

/// สิ่งที่นิสิตทำได้กับกิจกรรมหนึ่งบนปฏิทิน
enum CalendarStudentAction {
  /// เปิดรับอยู่และยังมีที่ — กดสมัครได้
  register,

  /// ที่นั่งเต็ม
  full,

  /// กิจกรรมเริ่มไปแล้ว — ปิดรับสมัคร
  closed,

  /// สมัครแล้วและยังยกเลิกได้
  cancel,

  /// สมัครแล้วแต่ยกเลิกไม่ได้ (เช็กอินแล้ว หรือหลักฐานอนุมัติแล้ว)
  locked,
}

/// ปุ่มฝั่งนิสิตของกิจกรรมนี้ — กติกาเดียวกับ backend
///
/// - สมัครแล้ว: ยกเลิกได้ถ้ายังไม่เช็กอินและยังไม่อนุมัติ (`DELETE /participations/{id}`
///   ปฏิเสธสองเคสนั้นอยู่แล้ว UI จึงไม่ล่อให้กด)
/// - ยังไม่สมัคร: สมัครแล้วมาก่อน "เต็ม" — คนที่สมัครไว้แล้วต้องยังยกเลิกได้แม้งานเต็ม
/// - เริ่มไปแล้ว = `start_at <= ตอนนี้` ตรงกับ `POST /participations/register`
///
/// [nowTh] ต้องเป็นเวลาไทยแบบไม่มีโซน ([thaiNowNaive]) เพราะ `start_at` เก็บแบบนั้น
CalendarStudentAction calendarStudentAction(
  Activity a,
  Participation? participation, {
  required DateTime nowTh,
}) {
  if (participation != null) {
    final cancelable =
        participation.checkInTime == null && participation.evidenceStatus != 'approved';
    return cancelable ? CalendarStudentAction.cancel : CalendarStudentAction.locked;
  }
  if (a.isFull) return CalendarStudentAction.full;
  if (!a.startAt.isAfter(nowTh)) return CalendarStudentAction.closed;
  return CalendarStudentAction.register;
}

DateTime _endOf(Activity a) =>
    a.startAt.add(Duration(minutes: math.max((a.hours * 60).round(), 1)));

/// กิจกรรมที่สมัครไว้แล้วซึ่งช่วงเวลาทับกับ [target] ในวันเดียวกัน (ไม่นับตัวมันเอง)
///
/// งานที่จบพอดีตอนอีกงานเริ่ม (09:00–12:00 กับ 12:00–15:00) ไม่ถือว่าชน
List<Activity> calendarTimeConflicts(Activity target, Iterable<Activity> registered) {
  final conflicts = [
    for (final other in registered)
      if (other.id != target.id &&
          _sameDay(other.startAt, target.startAt) &&
          other.startAt.isBefore(_endOf(target)) &&
          target.startAt.isBefore(_endOf(other)))
        other,
  ];
  conflicts.sort((a, b) => a.startAt.compareTo(b.startAt));
  return conflicts;
}

/// query ของ `GET /activities` สำหรับปฏิทิน — ทุก role เห็นกิจกรรมชุดเดียวกัน
///
/// staff: ค่าเริ่มของ backend คือเฉพาะกิจกรรมที่ตัวเองสร้าง (หน้าจัดการกิจกรรมใช้แบบนั้น)
/// ปฏิทินจึงขอ `all_owners` ให้เห็นเท่า admin · admin เห็นทุกอันอยู่แล้ว · นิสิตยังเห็นเฉพาะ
/// ที่อนุมัติ/ไม่ซ่อน (backend กรองเอง พารามิเตอร์นี้ไม่มีผล) จึงไม่ต้องส่ง
Map<String, String>? calendarActivitiesQuery(String? role) =>
    role == 'staff' ? const {'all_owners': 'true'} : null;

/// ปุ่มจัดการของ staff/admin บนการ์ดกิจกรรม
enum CalendarStaffAction { approve, participants, edit }

/// ปุ่มจัดการตามสิทธิ์ — อนุมัติได้เฉพาะ admin และเฉพาะที่ยังไม่อนุมัติ (กติกาเดียวกับหน้าจัดการกิจกรรม)
///
/// staff เห็นกิจกรรมของทุกคนในปฏิทิน แต่ผู้เข้าร่วม/แก้ไขขึ้นเฉพาะอันที่จัดการได้
/// ([Activity.canManage] จาก backend — กติกาเดียวกับที่ endpoint ตอบ 403) ·
/// canManage = null (endpoint ไม่ได้ส่งมา) ถือว่าได้ เพราะรายการเดิมของ staff มีแต่ของตัวเอง
List<CalendarStaffAction> calendarStaffActions(
  Activity a, {
  required bool isAdmin,
  required bool canWrite,
}) =>
    [
      if (canApproveActivity(a.approvalStatus, isAdmin: isAdmin)) CalendarStaffAction.approve,
      if (canWrite && (isAdmin || a.canManage != false))
        ...[CalendarStaffAction.participants, CalendarStaffAction.edit],
    ];

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
/// ต่างกันแค่สีชิป, badge และปุ่มในการ์ดกิจกรรม:
/// - นิสิต: สมัครเข้าร่วม / ยกเลิกการสมัคร
/// - staff/admin: อนุมัติ (admin) / ผู้เข้าร่วม / แก้ไข
///
/// สิทธิ์จริงอยู่ที่ backend เหมือนเดิม: `GET /activities` กรองตาม role อยู่แล้ว
/// และ endpoint สมัคร/ยกเลิก/อนุมัติ ตรวจ role เอง — ปุ่มที่ซ่อนในหน้านี้เป็นแค่ UX
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

  /// กิจกรรมที่กำลังรอผลสมัคร/ยกเลิก/อนุมัติ — ปิดปุ่มไว้กันกดซ้ำ
  final Set<int> _busy = {};
  late DateTime _month;
  late DateTime _selectedDay;
  bool _loading = false;
  String? _error;

  DateTime get _today => activityDayKey(DateTime.now());
  bool get _isStudent => authService.role == 'student';

  /// โหมดเทสต์ไม่มี API ให้ซิงก์ข้อมูลกลับ
  bool get _canSync => widget.initialActivities == null;

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

  /// โหลดทุกอย่างใหม่ — [silent] = ซิงก์เงียบ ๆ หลังสมัคร/ยกเลิก ไม่ล้างหน้าจอเป็นตัวหมุน
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final activities = await ApiService.fetchAll(
        '/activities',
        Activity.fromJson,
        query: calendarActivitiesQuery(authService.role),
      );
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

      if (!mounted) return;
      setState(() {
        _byDay
          ..clear()
          ..addAll(groupActivitiesByDay(activities));
        _categories = categories;
        _criteriaSets = criteriaSets;
        _ownParticipationByActivity = {for (final p in participations) p.activityId: p};
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        showErrorSnackbar(context, e);
      } else {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  List<Activity> _activitiesOn(DateTime day) => _byDay[activityDayKey(day)] ?? const [];

  Iterable<Activity> get _registeredActivities => _byDay.values
      .expand((list) => list)
      .where((a) => _ownParticipationByActivity.containsKey(a.id));

  /// แทนกิจกรรมเดิมในรายการของวัน (หลังสมัคร/ยกเลิก/อนุมัติ) โดยไม่ต้องโหลดใหม่ทั้งหน้า
  void _replaceActivity(Activity updated) {
    final list = _byDay[activityDayKey(updated.startAt)];
    if (list == null) return;
    final index = list.indexWhere((a) => a.id == updated.id);
    if (index >= 0) list[index] = updated;
  }

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

  /// ทำงานกับ API ของกิจกรรม [id] โดยปิดปุ่มระหว่างรอ แล้วซิงก์ข้อมูลจริงกลับแบบเงียบ
  Future<void> _runBusy(int id, Future<void> Function() action) async {
    setState(() => _busy.add(id));
    try {
      await action();
    } catch (e) {
      // เต็มพอดี / หมดเวลา / เน็ตหลุด → แจ้งด้วย snackbar ไม่ทำทั้งหน้าพัง
      if (mounted) showErrorSnackbar(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
    // ที่นั่งจริงอาจเปลี่ยนจากคนอื่นสมัครพร้อมกัน — ดึงของจริงมาทับค่าที่ขยับไว้ในจอ
    if (mounted && _canSync) await _load(silent: true);
  }

  Future<void> _register(Activity a) async {
    final id = a.id;
    if (id == null) return;
    final conflicts = calendarTimeConflicts(a, _registeredActivities);
    final confirmed = await confirmAction(
      context,
      title: conflicts.isEmpty ? 'ยืนยันการสมัคร' : 'เวลาชนกับกิจกรรมที่สมัครไว้',
      message: 'สมัครเข้าร่วม "${a.name}"\n'
          '${thaiFullDateLabel(a.startAt)}\n'
          '${activityTimeRange(a)} • ${a.location}\n\n'
          'ได้ ${formatHours(a.hours)} ชั่วโมง\n'
          'นับเข้าหมวด ${activityCriteriaLabel(_categories, _criteriaSets, a)}',
      detail: [
        for (final c in conflicts) '⚠ ชนกับ "${c.name}" (${activityTimeRange(c)})',
        'ชั่วโมงจะถูกนับเมื่อหลักฐานผ่านการอนุมัติ',
      ].join('\n'),
      confirmLabel: conflicts.isEmpty ? 'สมัคร' : 'สมัครต่อ',
      icon: conflicts.isEmpty ? Icons.how_to_reg : Icons.warning_amber_rounded,
    );
    if (confirmed != true || !mounted) return;

    await _runBusy(id, () async {
      final participation = await ApiService.create(
        '/participations/register',
        {'activity_id': id},
        Participation.fromJson,
      );
      if (!mounted) return;
      setState(() {
        _ownParticipationByActivity[id] = participation;
        _replaceActivity(a.copyWith(participantCount: a.participantCount + 1));
      });
      showInfoSnackbar(context, 'สมัคร "${a.name}" แล้ว');
    });
  }

  Future<void> _cancel(Participation p, Activity a) async {
    final id = a.id;
    if (id == null || p.id == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'ยืนยันการยกเลิก',
      message: 'ยกเลิกการสมัคร "${a.name}"\n${activityTimeRange(a)} • ${a.location}',
      detail: 'ที่นั่งจะคืนให้คนอื่นสมัครได้ ถ้าเปลี่ยนใจต้องสมัครใหม่ (ถ้ายังมีที่ว่าง)',
      confirmLabel: 'ยกเลิกการสมัคร',
      icon: Icons.cancel_outlined,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    await _runBusy(id, () async {
      await ApiService.delete('/participations/${p.id}');
      if (!mounted) return;
      setState(() {
        _ownParticipationByActivity.remove(id);
        _replaceActivity(a.copyWith(participantCount: math.max(0, a.participantCount - 1)));
      });
      showInfoSnackbar(context, 'ยกเลิกการสมัคร "${a.name}" แล้ว');
    });
  }

  Future<void> _approve(Activity a) async {
    final id = a.id;
    if (id == null) return;
    await _runBusy(id, () async {
      final approved = await ApiService.patch('/activities/$id/approve', Activity.fromJson);
      if (!mounted) return;
      setState(() => _replaceActivity(approved));
      showInfoSnackbar(context, 'อนุมัติ "${a.name}" แล้ว');
    });
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
        AppIconButton(icon: Icons.refresh, tooltip: 'โหลดใหม่', onPressed: () => _load()),
      ],
      child: _loading
          ? const LoadingState(message: 'กำลังโหลดปฏิทิน...')
          : _error != null
              ? ErrorState(message: _error!, onRetry: () => _load())
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

  Widget _icon(IconData icon, {required bool busy}) => busy
      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(icon, size: 16);

  /// ห่อปุ่มในการ์ดให้ semantics บอกชื่อกิจกรรมด้วย — "สมัครเข้าร่วม: <ชื่อกิจกรรม>"
  ///
  /// แผงวันมีปุ่ม "สมัครเข้าร่วม" หลายอันหน้าตาเหมือนกัน screen reader (และเครื่องมือทดสอบ
  /// ที่อ่าน semantics) จะแยกไม่ออกว่าปุ่มไหนเป็นของกิจกรรมไหน · การกดด้วยนิ้ว/เมาส์ไม่เปลี่ยน
  ///
  /// ต้องเป็น `container` — การ์ดที่มีปุ่มเดียว (ฝั่งนิสิต) Flutter จะรวมปุ่มเข้ากับข้อความทั้งการ์ด
  /// เป็น node เดียว ปุ่มจึงไม่มีตัวตนของตัวเองให้โฟกัส/กด
  Widget _labelled(Activity a, String label, VoidCallback? onPressed, Widget button) => Semantics(
        container: true,
        label: '$label: ${a.name}',
        button: true,
        enabled: onPressed != null,
        onTap: onPressed,
        excludeSemantics: true,
        child: button,
      );

  /// ปุ่มในการ์ดตาม role — นิสิตสมัคร/ยกเลิก · staff/admin อนุมัติ/ผู้เข้าร่วม/แก้ไข
  List<Widget> _cardActions(Activity a) {
    final id = a.id;
    final busy = id != null && _busy.contains(id);

    if (_isStudent) {
      final participation = _ownParticipationByActivity[id];
      final action = calendarStudentAction(a, participation, nowTh: thaiNowNaive());
      final VoidCallback? register = busy ? null : () => _register(a);
      final VoidCallback? cancel =
          busy || participation == null ? null : () => _cancel(participation, a);
      return [
        switch (action) {
          CalendarStudentAction.register => _labelled(
              a,
              'สมัครเข้าร่วม',
              register,
              FilledButton.icon(
                onPressed: register,
                style: _cardButtonStyle,
                icon: _icon(Icons.add, busy: busy),
                label: const Text('สมัครเข้าร่วม'),
              ),
            ),
          CalendarStudentAction.full => _labelled(
              a,
              'เต็มแล้ว',
              null,
              FilledButton.icon(
                onPressed: null,
                style: _cardButtonStyle,
                icon: const Icon(Icons.group_off_outlined, size: 16),
                label: const Text('เต็มแล้ว'),
              ),
            ),
          CalendarStudentAction.closed => _labelled(
              a,
              'ปิดรับสมัครแล้ว',
              null,
              FilledButton.icon(
                onPressed: null,
                style: _cardButtonStyle,
                icon: const Icon(Icons.lock_clock, size: 16),
                label: const Text('ปิดรับสมัครแล้ว'),
              ),
            ),
          CalendarStudentAction.cancel => _labelled(
              a,
              'ยกเลิกการสมัคร',
              cancel,
              OutlinedButton.icon(
                onPressed: cancel,
                style: _cardButtonStyle.merge(AppButtonStyles.danger(context)),
                icon: _icon(Icons.close, busy: busy),
                label: const Text('ยกเลิกการสมัคร'),
              ),
            ),
          CalendarStudentAction.locked => _labelled(
              a,
              'ยกเลิกไม่ได้',
              null,
              Tooltip(
                message: 'เช็กอินหรือหลักฐานได้รับอนุมัติแล้ว จึงยกเลิกไม่ได้',
                child: OutlinedButton.icon(
                  onPressed: null,
                  style: _cardButtonStyle,
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: const Text('ยกเลิกไม่ได้'),
                ),
              ),
            ),
        },
      ];
    }

    final actions = calendarStaffActions(
      a,
      isAdmin: authService.role == 'admin',
      canWrite: authService.canWrite,
    );
    final VoidCallback? approve = busy ? null : () => _approve(a);
    void participants() => _openParticipants(a);
    void edit() => _edit(a);
    return [
      for (final action in actions)
        switch (action) {
          CalendarStaffAction.approve => _labelled(
              a,
              'อนุมัติ',
              approve,
              FilledButton.icon(
                onPressed: approve,
                style: _cardButtonStyle,
                icon: _icon(Icons.check_circle_outline, busy: busy),
                label: const Text('อนุมัติ'),
              ),
            ),
          CalendarStaffAction.participants => _labelled(
              a,
              'ผู้เข้าร่วม',
              participants,
              OutlinedButton.icon(
                onPressed: participants,
                style: _cardButtonStyle,
                icon: const Icon(Icons.groups_outlined, size: 16),
                label: const Text('ผู้เข้าร่วม'),
              ),
            ),
          CalendarStaffAction.edit => _labelled(
              a,
              'แก้ไข',
              edit,
              OutlinedButton.icon(
                onPressed: edit,
                style: _cardButtonStyle,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('แก้ไข'),
              ),
            ),
        },
    ];
  }
}
