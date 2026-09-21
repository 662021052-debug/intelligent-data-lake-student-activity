import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/participation.dart';
import 'package:activity_tracking_frontend/screens/activity_calendar_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/format.dart';
import 'package:activity_tracking_frontend/widgets/app_nav.dart';
import 'package:activity_tracking_frontend/widgets/app_sidebar.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ปฏิทินเปิดที่ "เดือนปัจจุบัน" เสมอ เทสต์จึงวางกิจกรรมไว้กลางเดือนนั้น (วันที่ 15)
DateTime get _day {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 15);
}

DateTime _at(int hour, int minute, {DateTime? on}) {
  final d = on ?? _day;
  return DateTime(d.year, d.month, d.day, hour, minute);
}

/// วันที่ 15 ของเดือนถัดไป — อยู่ในอนาคตเสมอ ใช้กับเคส "ยังเปิดรับสมัคร"
DateTime get _nextMonthDay {
  final now = DateTime.now();
  return DateTime(now.year, now.month + 1, 15);
}

int get _thaiYear => _day.year + 543;

Activity _activity({
  int id = 1,
  String name = 'อบรมปฐมพยาบาล',
  required DateTime startAt,
  String location = 'ห้องประชุม ชั้น 3',
  String approvalStatus = 'pending',
  double hours = 6,
  int maxParticipants = 120,
  int participantCount = 0,
  bool isHidden = false,
  bool? canManage,
  DateTime? endAt,
}) =>
    Activity(
      id: id,
      name: name,
      activityType: 'อบรม/สัมมนา',
      hours: hours,
      maxParticipants: maxParticipants,
      participantCount: participantCount,
      startAt: startAt,
      endAt: endAt,
      location: location,
      approvalStatus: approvalStatus,
      isHidden: isHidden,
      canManage: canManage,
    );

void _loginAs(String role) {
  authService.token = 'fake-token';
  authService.username = role;
  authService.role = role;
}

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(
  WidgetTester tester,
  List<Activity> activities, {
  List<Participation> participations = const [],
  Size size = const Size(1400, 1000),
}) async {
  _screen(tester, size);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: ActivityCalendarScreen(
      initialActivities: activities,
      initialParticipations: participations,
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _cell(DateTime day) => find.byKey(ValueKey('calendar-day-${calendarDayId(day)}'));
final Finder _panel = find.byKey(const ValueKey('calendar-day-panel'));
Finder _inPanel(Finder f) => find.descendant(of: _panel, matching: f);
Finder _inCell(DateTime day, Finder f) => find.descendant(of: _cell(day), matching: f);

Future<void> _tapDay(WidgetTester tester, DateTime day) async {
  await tester.tap(_cell(day));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => authService.logout());

  group('เมนูปฏิทินของแอดมิน', () {
    test('role admin มี "ปฏิทินกิจกรรม" อยู่ในเมนู', () {
      final ids = navItemsForRole('admin').map((i) => i.id).toList();
      expect(ids, contains('calendar'));
    });

    test('วางต่อจาก "จัดการกิจกรรม" เพราะเป็นข้อมูลชุดเดียวกันคนละมุมมอง', () {
      final ids = navItemsForRole('admin').map((i) => i.id).toList();
      expect(ids.indexOf('calendar'), ids.indexOf('activities') + 1);
    });

    test('เมนูเดิมของแอดมินยังอยู่ครบ ไม่ได้ไปแทนที่อันไหน', () {
      final ids = navItemsForRole('admin').map((i) => i.id).toList();
      for (final id in ['dashboard', 'activities', 'users', 'students', 'hour_categories']) {
        expect(ids, contains(id), reason: 'เมนู $id หายไป');
      }
    });

    test('staff ยังมีปฏิทินเหมือนเดิม · นิสิตมีในเมนูแล้ว', () {
      expect(navItemsForRole('staff').map((i) => i.id), contains('calendar'));
      expect(navItemsForRole('student').map((i) => i.id), contains('calendar'));
    });

    testWidgets('sidebar ของแอดมินขึ้นเมนู "ปฏิทินกิจกรรม" จริง', (tester) async {
      _screen(tester, const Size(1400, 1000));
      _loginAs('admin');

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppSidebar(
            items: navItemsForRole('admin'),
            activeId: 'dashboard',
            username: 'admin',
            role: 'admin',
            subtitle: navSubtitleForRole('admin'),
            groupTitle: navGroupTitleForRole('admin'),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ปฏิทินกิจกรรม'), findsOneWidget);
    });
  });

  group('จัดกลุ่มกิจกรรมตามวัน', () {
    test('กิจกรรมคนละเวลาในวันเดียวกันอยู่กลุ่มเดียวกัน', () {
      final grouped = groupActivitiesByDay([
        _activity(id: 1, startAt: DateTime(2027, 2, 1, 13, 0)),
        _activity(id: 2, startAt: DateTime(2027, 2, 1, 9, 0)),
        _activity(id: 3, startAt: DateTime(2027, 2, 2, 9, 0)),
      ]);

      expect(grouped.length, 2);
      expect(grouped[activityDayKey(DateTime(2027, 2, 1))]!.length, 2);
      expect(grouped[activityDayKey(DateTime(2027, 2, 2))]!.length, 1);
    });

    test('ภายในวันเรียงตามเวลาเริ่ม ไม่ใช่ลำดับที่ API ส่งมา', () {
      final grouped = groupActivitiesByDay([
        _activity(id: 1, name: 'บ่าย', startAt: DateTime(2027, 2, 1, 13, 0)),
        _activity(id: 2, name: 'เช้า', startAt: DateTime(2027, 2, 1, 9, 0)),
      ]);

      final names =
          grouped[activityDayKey(DateTime(2027, 2, 1))]!.map((a) => a.name).toList();
      expect(names, ['เช้า', 'บ่าย']);
    });

    test('ไม่มีกิจกรรมเลยได้แผนที่ว่าง ไม่ใช่ระเบิด', () {
      expect(groupActivitiesByDay([]), isEmpty);
    });
  });

  group('ตารางเดือน — เริ่มวันจันทร์ เต็มสัปดาห์เสมอ', () {
    test('ก.ย. 2569 เริ่ม 1 ก.ย. วันอังคาร → วาดจาก 31 ส.ค. ถึง 4 ต.ค. (5 สัปดาห์)', () {
      final days = calendarMonthDays(DateTime(2026, 9));
      expect(days.length, 35);
      expect(days.first, DateTime.utc(2026, 8, 31));
      expect(days.last, DateTime.utc(2026, 10, 4));
      expect(days.first.weekday, DateTime.monday);
      expect(days.last.weekday, DateTime.sunday);
    });

    test('ก.พ. 2570 พอดี 4 สัปดาห์ ไม่มีวันของเดือนข้างเคียง', () {
      final days = calendarMonthDays(DateTime(2027, 2));
      expect(days.length, 28);
      expect(days.first, DateTime.utc(2027, 2, 1));
      expect(days.last, DateTime.utc(2027, 2, 28));
    });

    test('ส.ค. 2569 ต้องใช้ 6 สัปดาห์', () {
      final days = calendarMonthDays(DateTime(2026, 8));
      expect(days.length, 42);
      expect(days.first, DateTime.utc(2026, 7, 27));
      expect(days.last, DateTime.utc(2026, 9, 6));
    });
  });

  group('ข้อความในแผงวัน', () {
    test('หัวแผงเป็นชื่อวันเต็ม + ปี พ.ศ.', () {
      expect(thaiFullDateLabel(DateTime(2026, 9, 14)), 'วันจันทร์ที่ 14 กันยายน 2569');
      expect(thaiFullDateLabel(DateTime(2027, 2, 28)), 'วันอาทิตย์ที่ 28 กุมภาพันธ์ 2570');
    });

    test('ช่วงเวลาคิดเวลาจบจากชั่วโมงของกิจกรรม', () {
      expect(activityTimeRange(_activity(startAt: DateTime(2026, 9, 14, 9), hours: 3)),
          '09:00–12:00 น.');
      expect(activityTimeRange(_activity(startAt: DateTime(2026, 9, 14, 13), hours: 1.5)),
          '13:00–14:30 น.');
      expect(activityTimeRange(_activity(startAt: DateTime(2026, 9, 14, 9), hours: 0)), '09:00 น.');
    });

    test('มีเวลาสิ้นสุด → ใช้ค่านั้นแทนที่ประมาณจากชั่วโมง', () {
      final a = _activity(
        startAt: DateTime(2026, 9, 14, 9),
        endAt: DateTime(2026, 9, 14, 10, 15),
        hours: 3,
      );
      expect(activityTimeRange(a), '09:00–10:15 น.');
    });

    test('ที่นั่ง: เหลือกี่ที่ / เต็มแล้ว', () {
      expect(activitySeatsLabel(_activity(startAt: _day, maxParticipants: 10, participantCount: 1)),
          'เหลือ 9 / 10');
      expect(activitySeatsLabel(_activity(startAt: _day, maxParticipants: 15, participantCount: 15)),
          'เต็มแล้ว 15 / 15');
      expect(activitySeatsLeft(_activity(startAt: _day, maxParticipants: 15, participantCount: 16)), 0,
          reason: 'ข้อมูลเก่าที่รับเกินความจุต้องไม่ขึ้นที่นั่งติดลบ');
    });
  });

  group('สีชิปตาม role', () {
    final approved = _activity(startAt: _day, approvalStatus: 'approved');
    final pending = _activity(startAt: _day, approvalStatus: 'pending');

    test('นิสิต: ฟ้า = ยังไม่สมัคร · เขียว = สมัครแล้ว', () {
      expect(calendarChipPalette(approved, isStudent: true), StatusPalette.info);
      expect(calendarChipPalette(approved, isStudent: true, registered: true), StatusPalette.approved);
    });

    test('staff/admin: เขียว = อนุมัติ · เหลือง = รออนุมัติ · เทา = ซ่อนอยู่', () {
      expect(calendarChipPalette(approved, isStudent: false), StatusPalette.approved);
      expect(calendarChipPalette(pending, isStudent: false), StatusPalette.pending);
      expect(
        calendarChipPalette(_activity(startAt: _day, approvalStatus: 'approved', isHidden: true),
            isStudent: false),
        StatusPalette.neutral,
      );
    });
  });

  group('ช่องวันแสดงชื่อกิจกรรมจริง', () {
    testWidgets('ชิปชื่อกิจกรรมอยู่ในช่องวัน · เกิน 2 อันรวมเป็น "+N เพิ่ม"', (tester) async {
      _loginAs('admin');
      await _pump(tester, [
        _activity(id: 1, name: 'อบรมปฐมพยาบาล', startAt: _at(9, 0)),
        _activity(id: 2, name: 'ค่ายอาสา', startAt: _at(13, 0)),
        _activity(id: 3, name: 'สัมมนาวิชาการ', startAt: _at(15, 0)),
      ]);

      expect(_inCell(_day, find.text('อบรมปฐมพยาบาล')), findsOneWidget);
      expect(_inCell(_day, find.text('ค่ายอาสา')), findsOneWidget);
      expect(_inCell(_day, find.text('สัมมนาวิชาการ')), findsNothing,
          reason: 'อันที่ 3 ต้องรวมอยู่ใน "+1 เพิ่ม"');
      expect(_inCell(_day, find.text('+1 เพิ่ม')), findsOneWidget);
    });

    testWidgets('ช่องวันจอกว้างสูงอย่างน้อย 96px', (tester) async {
      _loginAs('admin');
      await _pump(tester, [_activity(id: 1, startAt: _at(9, 0))]);
      expect(tester.getSize(_cell(_day)).height, greaterThanOrEqualTo(kCalendarCellMinHeight));
    });
  });

  group('กดวัน → แผงขวาแสดงรายการของวันนั้น', () {
    testWidgets('แอดมินเห็นชื่อ/เวลา/สถานที่/สถานะ/ที่นั่ง ของกิจกรรมในวันที่กด', (tester) async {
      _loginAs('admin');
      await _pump(tester, [
        _activity(id: 1, name: 'อบรมปฐมพยาบาล', startAt: _at(9, 30), participantCount: 2),
        _activity(
          id: 2,
          name: 'ค่ายอาสาพัฒนาชนบท',
          startAt: _at(13, 0),
          location: 'หอประชุมใหญ่',
          approvalStatus: 'approved',
        ),
        _activity(id: 3, name: 'กิจกรรมวันอื่น', startAt: _at(9, 0, on: DateTime(_day.year, _day.month, 20))),
      ]);

      await _tapDay(tester, _day);

      expect(_inPanel(find.text(thaiFullDateLabel(_day))), findsOneWidget);
      expect(_inPanel(find.text('มี 2 กิจกรรม')), findsOneWidget);
      expect(_inPanel(find.text('อบรมปฐมพยาบาล')), findsOneWidget);
      expect(_inPanel(find.text('ค่ายอาสาพัฒนาชนบท')), findsOneWidget);
      expect(_inPanel(find.textContaining('09:30–15:30 น.')), findsOneWidget);
      expect(_inPanel(find.textContaining('ห้องประชุม ชั้น 3')), findsOneWidget);
      expect(_inPanel(find.textContaining('หอประชุมใหญ่')), findsOneWidget);
      expect(_inPanel(find.widgetWithText(StatusChip, 'รออนุมัติ')), findsOneWidget);
      expect(_inPanel(find.widgetWithText(StatusChip, 'อนุมัติแล้ว')), findsOneWidget);
      expect(_inPanel(find.textContaining('เหลือ 118 / 120')), findsOneWidget);
      expect(_inPanel(find.text('กิจกรรมวันอื่น')), findsNothing,
          reason: 'กิจกรรมของวันอื่นต้องไม่หลุดมาปนในแผง');
    });

    testWidgets('แอดมินมีปุ่ม "ผู้เข้าร่วม" และ "แก้ไข" ในการ์ด', (tester) async {
      _loginAs('admin');
      await _pump(tester, [_activity(id: 1, startAt: _at(9, 30))]);
      await _tapDay(tester, _day);

      expect(_inPanel(find.widgetWithText(OutlinedButton, 'ผู้เข้าร่วม')), findsOneWidget);
      expect(_inPanel(find.widgetWithText(OutlinedButton, 'แก้ไข')), findsOneWidget);
      expect(_inPanel(find.text('สมัครเข้าร่วม')), findsNothing);
    });

    testWidgets('นิสิตไม่มีปุ่มจัดการ · กิจกรรมที่ยังเปิดรับมีปุ่ม "สมัครเข้าร่วม"', (tester) async {
      _loginAs('student');
      await _pump(tester, [
        _activity(id: 1, name: 'เปิดรับอยู่', startAt: _at(9, 0, on: _nextMonthDay), approvalStatus: 'approved'),
      ]);

      await tester.tap(find.byTooltip('เดือนถัดไป'));
      await tester.pumpAndSettle();
      await _tapDay(tester, _nextMonthDay);

      expect(_inPanel(find.text('เปิดรับอยู่')), findsOneWidget);
      expect(_inPanel(find.text('สมัครเข้าร่วม')), findsOneWidget);
      expect(_inPanel(find.text('ผู้เข้าร่วม')), findsNothing);
      expect(_inPanel(find.text('แก้ไข')), findsNothing);
    });

    testWidgets('นิสิต: กิจกรรมเต็มปุ่มถูกปิด · ที่สมัครแล้วขึ้น "สมัครแล้ว" ไม่มีปุ่มสมัครซ้ำ',
        (tester) async {
      _loginAs('student');
      await _pump(
        tester,
        [
          _activity(
            id: 1,
            name: 'เต็มแล้วนะ',
            startAt: _at(9, 0, on: _nextMonthDay),
            approvalStatus: 'approved',
            maxParticipants: 15,
            participantCount: 15,
          ),
          _activity(id: 2, name: 'สมัครไว้แล้ว', startAt: _at(13, 0, on: _nextMonthDay), approvalStatus: 'approved'),
        ],
        participations: [Participation(id: 9, studentId: 1, activityId: 2)],
      );
      await tester.tap(find.byTooltip('เดือนถัดไป'));
      await tester.pumpAndSettle();
      await _tapDay(tester, _nextMonthDay);

      final fullButton = tester.widget<ButtonStyleButton>(
        find.ancestor(of: _inPanel(find.text('เต็มแล้ว')), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
      );
      expect(fullButton.onPressed, isNull, reason: 'กิจกรรมเต็มต้องกดสมัครไม่ได้');
      expect(_inPanel(find.textContaining('เต็มแล้ว 15 / 15')), findsOneWidget);

      final registeredCard = find.byKey(const ValueKey('calendar-activity-2'));
      expect(find.descendant(of: registeredCard, matching: find.widgetWithText(StatusChip, 'สมัครแล้ว')),
          findsOneWidget);
      expect(find.descendant(of: registeredCard, matching: find.text('สมัครเข้าร่วม')), findsNothing);
    });

    testWidgets('วันที่ไม่มีกิจกรรมขึ้น "ไม่มีกิจกรรมในวันนี้" พร้อมวันที่ พ.ศ.', (tester) async {
      _loginAs('admin');
      await _pump(tester, [_activity(id: 1, startAt: _at(9, 30))]);

      await _tapDay(tester, DateTime(_day.year, _day.month, 16));

      expect(_inPanel(find.text('ไม่มีกิจกรรมในวันนี้')), findsOneWidget);
      expect(_inPanel(find.textContaining('$_thaiYear')), findsWidgets, reason: 'ปีต้องเป็น พ.ศ.');
      expect(_inPanel(find.textContaining('${_day.year}')), findsNothing,
          reason: 'ไม่ควรมีปี ค.ศ. หลงเหลือ');
    });
  });

  group('หัวปฏิทิน', () {
    testWidgets('เลื่อนเดือนด้วย ‹ › แล้วกด "วันนี้" กลับมาเดือนปัจจุบัน', (tester) async {
      _loginAs('admin');
      await _pump(tester, const []);
      final now = DateTime.now();
      final title = find.byKey(const ValueKey('calendar-month-title'));

      expect(tester.widget<Text>(title).data, thaiMonthTitle(now));

      await tester.tap(find.byTooltip('เดือนถัดไป'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(title).data, thaiMonthTitle(DateTime(now.year, now.month + 1)));

      await tester.tap(find.byTooltip('เดือนก่อนหน้า'));
      await tester.tap(find.byTooltip('เดือนก่อนหน้า'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(title).data, thaiMonthTitle(DateTime(now.year, now.month - 1)));

      await tester.tap(find.widgetWithText(OutlinedButton, 'วันนี้'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(title).data, thaiMonthTitle(now));
      expect(_inPanel(find.text(thaiFullDateLabel(now))), findsOneWidget);
    });
  });

  group('ปุ่มฝั่งนิสิต (งานที่ 2) — กติกาเดียวกับ backend', () {
    final nowTh = DateTime(2026, 10, 30, 10, 0);
    Activity future({int count = 0, int max = 10}) => _activity(
          startAt: DateTime(2026, 10, 31, 9),
          approvalStatus: 'approved',
          participantCount: count,
          maxParticipants: max,
        );
    Participation joined({DateTime? checkIn, String status = 'pending'}) =>
        Participation(id: 7, studentId: 1, activityId: 1, checkInTime: checkIn, evidenceStatus: status);

    test('เปิดรับ + มีที่ → สมัครได้', () {
      expect(calendarStudentAction(future(), null, nowTh: nowTh), CalendarStudentAction.register);
    });

    test('ที่นั่งเต็ม → สมัครไม่ได้', () {
      expect(calendarStudentAction(future(count: 10), null, nowTh: nowTh), CalendarStudentAction.full);
    });

    test('ถึงเวลาเริ่มแล้ว → ปิดรับ (รวมวินาทีที่เริ่มพอดี)', () {
      final a = future();
      expect(calendarStudentAction(a, null, nowTh: a.startAt), CalendarStudentAction.closed);
      expect(calendarStudentAction(a, null, nowTh: a.startAt.add(const Duration(minutes: 1))),
          CalendarStudentAction.closed);
    });

    test('สมัครแล้ว → ยกเลิกได้ แม้งานจะเต็ม', () {
      expect(calendarStudentAction(future(count: 10), joined(), nowTh: nowTh), CalendarStudentAction.cancel);
    });

    test('เช็กอินแล้ว หรือหลักฐานอนุมัติแล้ว → ยกเลิกไม่ได้', () {
      expect(calendarStudentAction(future(), joined(checkIn: nowTh), nowTh: nowTh), CalendarStudentAction.locked);
      expect(calendarStudentAction(future(), joined(status: 'approved'), nowTh: nowTh),
          CalendarStudentAction.locked);
    });

    test('เวลาไทยจากนาฬิกา UTC: 03:30 UTC = 10:30 ไทย → งาน 10:00 ปิดรับแล้ว', () {
      final nowTh = thaiNowNaive(DateTime.utc(2026, 10, 31, 3, 30));
      expect(nowTh, DateTime(2026, 10, 31, 10, 30));
      final started = _activity(startAt: DateTime(2026, 10, 31, 10), approvalStatus: 'approved');
      expect(calendarStudentAction(started, null, nowTh: nowTh), CalendarStudentAction.closed,
          reason: 'ถ้าเทียบกับ UTC (03:30) จะยังสมัครได้ ซึ่งคือบั๊กเดิม');
    });
  });

  group('เตือนเวลาชนกับกิจกรรมที่สมัครไว้', () {
    Activity at(int id, int hour, {double hours = 3, int day = 31}) => _activity(
          id: id,
          name: 'งาน $id',
          startAt: DateTime(2026, 10, day, hour),
          hours: hours,
          approvalStatus: 'approved',
        );

    test('ช่วงเวลาทับกันในวันเดียวกัน = ชน', () {
      final conflicts = calendarTimeConflicts(at(1, 9), [at(2, 11), at(3, 13)]);
      expect(conflicts.map((a) => a.id), [2]);
    });

    test('จบพอดีตอนอีกงานเริ่มไม่นับว่าชน · วันอื่นไม่นับ · ไม่นับตัวเอง', () {
      expect(calendarTimeConflicts(at(1, 9), [at(2, 12)]), isEmpty);
      expect(calendarTimeConflicts(at(1, 9), [at(2, 9, day: 30)]), isEmpty);
      expect(calendarTimeConflicts(at(1, 9), [at(1, 9)]), isEmpty);
    });
  });

  group('ปุ่มฝั่ง staff/admin', () {
    final pending = _activity(startAt: _day, approvalStatus: 'pending');
    final approved = _activity(startAt: _day, approvalStatus: 'approved');

    test('admin: รออนุมัติมีปุ่มอนุมัติ · อนุมัติแล้วไม่มี', () {
      expect(calendarStaffActions(pending, isAdmin: true, canWrite: true),
          [CalendarStaffAction.approve, CalendarStaffAction.participants, CalendarStaffAction.edit]);
      expect(calendarStaffActions(approved, isAdmin: true, canWrite: true),
          [CalendarStaffAction.participants, CalendarStaffAction.edit]);
    });

    test('staff อนุมัติเองไม่ได้ (backend ตอบ 403 อยู่แล้ว)', () {
      expect(calendarStaffActions(pending, isAdmin: false, canWrite: true),
          [CalendarStaffAction.participants, CalendarStaffAction.edit]);
    });

    test('staff เห็นกิจกรรมคนอื่นในปฏิทินได้ แต่ไม่มีปุ่มผู้เข้าร่วม/แก้ไข (canManage=false)', () {
      final othersActivity = _activity(startAt: _day, approvalStatus: 'approved', canManage: false);
      final ownActivity = _activity(startAt: _day, approvalStatus: 'approved', canManage: true);
      expect(calendarStaffActions(othersActivity, isAdmin: false, canWrite: true), isEmpty);
      expect(calendarStaffActions(ownActivity, isAdmin: false, canWrite: true),
          [CalendarStaffAction.participants, CalendarStaffAction.edit]);
      // ของคนอื่นที่ยังรออนุมัติ: staff ก็ยังไม่มีปุ่มอนุมัติ
      expect(
          calendarStaffActions(_activity(startAt: _day, canManage: false), isAdmin: false, canWrite: true),
          isEmpty);
    });

    test('admin จัดการได้ทุกกิจกรรมเสมอ · นิสิตไม่มีปุ่มจัดการ', () {
      final othersPending = _activity(startAt: _day, approvalStatus: 'pending', canManage: false);
      expect(calendarStaffActions(othersPending, isAdmin: true, canWrite: true),
          [CalendarStaffAction.approve, CalendarStaffAction.participants, CalendarStaffAction.edit]);
      expect(calendarStaffActions(approved, isAdmin: false, canWrite: false), isEmpty);
    });
  });

  group('ปฏิทินขอกิจกรรมชุดเดียวกันทุก role', () {
    test('staff ขอ all_owners ให้เห็นเท่า admin · admin/นิสิตไม่ต้องส่ง', () {
      expect(calendarActivitiesQuery('staff'), {'all_owners': 'true'});
      expect(calendarActivitiesQuery('admin'), isNull);
      expect(calendarActivitiesQuery('student'), isNull);
    });

    test('Activity.fromJson อ่าน can_manage (ไม่ส่งมา = null)', () {
      Map<String, dynamic> json(Object? canManage) => {
            'id': 9,
            'name': 'x',
            'activity_type': 'วิชาการ',
            'max_participants': 10,
            'start_at': '2026-09-15T09:00:00',
            'location': 'ห้อง',
            'can_manage': ?canManage,
          };
      expect(Activity.fromJson(json(false)).canManage, isFalse);
      expect(Activity.fromJson(json(true)).canManage, isTrue);
      expect(Activity.fromJson(json(null)).canManage, isNull);
      expect(Activity.fromJson(json(false)).copyWith(participantCount: 3).canManage, isFalse);
    });

    testWidgets('admin เห็นปุ่ม "อนุมัติ" ของกิจกรรมที่รออยู่ · staff ไม่เห็น', (tester) async {
      _loginAs('admin');
      await _pump(tester, [_activity(id: 1, startAt: _at(9, 0), approvalStatus: 'pending')]);
      await _tapDay(tester, _day);
      expect(_inPanel(find.widgetWithText(FilledButton, 'อนุมัติ')), findsOneWidget);

      _loginAs('staff');
      await _pump(tester, [_activity(id: 1, startAt: _at(9, 0), approvalStatus: 'pending')]);
      await _tapDay(tester, _day);
      expect(_inPanel(find.text('อนุมัติ')), findsNothing);
      expect(_inPanel(find.text('ผู้เข้าร่วม')), findsOneWidget);
    });

    testWidgets('staff: กิจกรรมคนอื่นขึ้นในปฏิทินแต่ไม่มีปุ่มจัดการ · ของตัวเองยังจัดการได้', (tester) async {
      _loginAs('staff');
      await _pump(tester, [
        _activity(id: 1, name: 'ของ admin', startAt: _at(9, 0), approvalStatus: 'approved', canManage: false),
        _activity(id: 2, name: 'ของฉันเอง', startAt: _at(13, 0), approvalStatus: 'approved', canManage: true),
      ]);
      await _tapDay(tester, _day);

      final others = find.byKey(const ValueKey('calendar-activity-1'));
      final own = find.byKey(const ValueKey('calendar-activity-2'));
      expect(others, findsOneWidget, reason: 'staff ต้องเห็นกิจกรรมของคนอื่นในปฏิทิน');
      expect(find.descendant(of: others, matching: find.text('ของ admin')), findsOneWidget);
      expect(find.descendant(of: others, matching: find.text('ผู้เข้าร่วม')), findsNothing);
      expect(find.descendant(of: others, matching: find.text('แก้ไข')), findsNothing);
      expect(find.descendant(of: own, matching: find.text('ผู้เข้าร่วม')), findsOneWidget);
      expect(find.descendant(of: own, matching: find.text('แก้ไข')), findsOneWidget);
    });
  });

  group('ป้ายปุ่มในปฏิทินใช้ฟอนต์ Sarabun (ไม่พึ่ง Roboto/ฟอนต์สำรองที่โหลดตอนรัน)', () {
    String? familyOf(WidgetTester tester, Finder label) =>
        DefaultTextStyle.of(tester.element(label)).style.fontFamily;

    testWidgets('แอดมิน: "ผู้เข้าร่วม" "แก้ไข" และปุ่ม "วันนี้" ที่หัวปฏิทิน', (tester) async {
      _loginAs('admin');
      await _pump(tester, [_activity(id: 1, startAt: _at(9, 30))]);
      await _tapDay(tester, _day);

      for (final label in [
        _inPanel(find.text('ผู้เข้าร่วม')),
        _inPanel(find.text('แก้ไข')),
        find.widgetWithText(OutlinedButton, 'วันนี้'),
      ]) {
        expect(label, findsOneWidget);
        expect(familyOf(tester, label), startsWith('Sarabun'), reason: 'ปุ่ม $label ไม่ได้ใช้ Sarabun');
      }
    });

    testWidgets('นิสิต: "สมัครเข้าร่วม" และ "ยกเลิกการสมัคร"', (tester) async {
      _loginAs('student');
      await _pump(
        tester,
        [
          _activity(id: 1, name: 'เปิดรับ', startAt: _at(9, 0, on: _nextMonthDay), approvalStatus: 'approved'),
          _activity(id: 2, name: 'สมัครแล้ว', startAt: _at(13, 0, on: _nextMonthDay), approvalStatus: 'approved'),
        ],
        participations: [Participation(id: 11, studentId: 1, activityId: 2)],
      );
      await tester.tap(find.byTooltip('เดือนถัดไป'));
      await tester.pumpAndSettle();
      await _tapDay(tester, _nextMonthDay);

      for (final label in [
        _inPanel(find.text('สมัครเข้าร่วม')),
        _inPanel(find.text('ยกเลิกการสมัคร')),
      ]) {
        expect(label, findsOneWidget);
        expect(familyOf(tester, label), startsWith('Sarabun'), reason: 'ปุ่ม $label ไม่ได้ใช้ Sarabun');
      }
    });
  });

  group('การ์ดนิสิตหลังสมัคร', () {
    testWidgets('สมัครแล้ว (ยังไม่เช็กอิน) มีปุ่ม "ยกเลิกการสมัคร" · เช็กอินแล้วยกเลิกไม่ได้', (tester) async {
      _loginAs('student');
      await _pump(
        tester,
        [
          _activity(id: 1, name: 'ยกเลิกได้', startAt: _at(9, 0, on: _nextMonthDay), approvalStatus: 'approved'),
          _activity(id: 2, name: 'เช็กอินแล้ว', startAt: _at(13, 0, on: _nextMonthDay), approvalStatus: 'approved'),
        ],
        participations: [
          Participation(id: 11, studentId: 1, activityId: 1),
          Participation(id: 12, studentId: 1, activityId: 2, checkInTime: DateTime(2026, 1, 1)),
        ],
      );
      await tester.tap(find.byTooltip('เดือนถัดไป'));
      await tester.pumpAndSettle();
      await _tapDay(tester, _nextMonthDay);

      final cancelable = find.byKey(const ValueKey('calendar-activity-1'));
      final locked = find.byKey(const ValueKey('calendar-activity-2'));
      final cancelButton = tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.descendant(of: cancelable, matching: find.text('ยกเลิกการสมัคร')),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ));
      expect(cancelButton.onPressed, isNotNull);

      final lockedButton = tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.descendant(of: locked, matching: find.text('ยกเลิกไม่ได้')),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ));
      expect(lockedButton.onPressed, isNull);
      expect(find.descendant(of: locked, matching: find.text('ยกเลิกการสมัคร')), findsNothing);
    });
  });

  test('Activity.copyWith เปลี่ยนเฉพาะจำนวนผู้สมัคร ค่าอื่นคงเดิม', () {
    final a = _activity(id: 5, startAt: _day, participantCount: 3, maxParticipants: 10);
    final b = a.copyWith(participantCount: 4);
    expect(b.participantCount, 4);
    expect([b.id, b.name, b.startAt, b.maxParticipants, b.approvalStatus],
        [a.id, a.name, a.startAt, a.maxParticipants, a.approvalStatus]);
  });

  group('ปุ่มในการ์ดบอกชื่อกิจกรรมผ่าน semantics', () {
    testWidgets('ปุ่มสมัครของแต่ละการ์ดแยกกันได้ด้วยชื่อกิจกรรม', (tester) async {
      final semantics = tester.ensureSemantics();
      _loginAs('student');
      await _pump(tester, [
        _activity(id: 1, name: 'งานเช้า', startAt: _at(9, 0, on: _nextMonthDay), approvalStatus: 'approved'),
        _activity(id: 2, name: 'งานบ่าย', startAt: _at(13, 0, on: _nextMonthDay), approvalStatus: 'approved'),
      ]);
      await tester.tap(find.byTooltip('เดือนถัดไป'));
      await tester.pumpAndSettle();
      await _tapDay(tester, _nextMonthDay);

      expect(find.bySemanticsLabel('สมัครเข้าร่วม: งานเช้า'), findsOneWidget);
      expect(find.bySemanticsLabel('สมัครเข้าร่วม: งานบ่าย'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('ปุ่มจัดการของ admin ก็บอกชื่อกิจกรรม', (tester) async {
      final semantics = tester.ensureSemantics();
      _loginAs('admin');
      await _pump(tester, [_activity(id: 1, name: 'ค่ายอาสา', startAt: _at(9, 0), approvalStatus: 'pending')]);
      await _tapDay(tester, _day);

      expect(find.bySemanticsLabel('อนุมัติ: ค่ายอาสา'), findsOneWidget);
      expect(find.bySemanticsLabel('ผู้เข้าร่วม: ค่ายอาสา'), findsOneWidget);
      expect(find.bySemanticsLabel('แก้ไข: ค่ายอาสา'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('layout', () {
    testWidgets('จอกว้าง: แผงวันอยู่ขวาของปฏิทิน กว้าง 348px', (tester) async {
      _loginAs('admin');
      await _pump(tester, [_activity(id: 1, startAt: _at(9, 0))]);

      final calendar = tester.getRect(find.byKey(const ValueKey('calendar-month')));
      final panel = tester.getRect(_panel);
      expect(panel.left, greaterThan(calendar.right));
      expect(panel.width, moreOrLessEquals(kCalendarDayPanelWidth, epsilon: 1));
    });

    testWidgets('จอ 360px: ซ้อนคอลัมน์เดียว ไม่ล้น แม้ชื่อกิจกรรมยาวหลายอัน', (tester) async {
      _loginAs('student');
      await _pump(
        tester,
        [
          for (var i = 0; i < 5; i++)
            _activity(
              id: i + 1,
              name: 'กิจกรรมชื่อยาวมากเพื่อทดสอบการตัดข้อความไม่ให้ล้นช่องวันลำดับที่ $i',
              startAt: _at(8 + i, 0),
              approvalStatus: 'approved',
            ),
        ],
        size: const Size(360, 740),
      );
      expect(tester.takeException(), isNull);

      await _tapDay(tester, _day);
      expect(tester.takeException(), isNull);

      final calendar = tester.getRect(find.byKey(const ValueKey('calendar-month')));
      final panel = tester.getRect(_panel);
      expect(panel.top, greaterThanOrEqualTo(calendar.bottom), reason: 'แผงวันต้องอยู่ใต้ปฏิทิน');
      expect(_inCell(_day, find.textContaining('กิจกรรมชื่อยาว')), findsNothing,
          reason: 'ช่องแคบใช้แถบสีแทนชิปชื่อ');
      expect(_inCell(_day, find.text('+2')), findsOneWidget);
    });
  });
}
