import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/screens/activity_calendar_screen.dart';
import 'package:activity_tracking_frontend/services/auth_service.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_nav.dart';
import 'package:activity_tracking_frontend/widgets/app_sidebar.dart';
import 'package:activity_tracking_frontend/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

/// ปฏิทินเปิดที่ "เดือนปัจจุบัน" เสมอ เทสต์จึงต้องวางกิจกรรมไว้ในเดือนนั้น
/// ไม่งั้นต้องกดเลื่อนเดือนก่อน ซึ่งทำให้เทสต์เปราะโดยไม่ได้เพิ่มความมั่นใจอะไร
///
/// เลือกวันที่ 15 เพราะเป็นกลางเดือน — ตัวเลขนี้ปรากฏครั้งเดียวในตารางเดือน
/// (วันต้น/ท้ายเดือนอาจซ้ำกับวันของเดือนข้างเคียงที่ปฏิทินวาดจาง ๆ ไว้)
DateTime get _day {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 15);
}

DateTime _at(int hour, int minute) =>
    DateTime(_day.year, _day.month, _day.day, hour, minute);

/// ปีพุทธศักราชของเดือนที่กำลังทดสอบ
int get _thaiYear => _day.year + 543;

Activity _activity({
  int id = 1,
  String name = 'อบรมปฐมพยาบาล',
  required DateTime startAt,
  String location = 'ห้องประชุม ชั้น 3',
  String approvalStatus = 'pending',
}) =>
    Activity(
      id: id,
      name: name,
      activityType: 'อบรม/สัมมนา',
      hours: 6,
      maxParticipants: 120,
      startAt: startAt,
      location: location,
      approvalStatus: approvalStatus,
    );

void _loginAs(String role) {
  authService.token = 'fake-token';
  authService.username = role;
  authService.role = role;
}

void _wideScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _calendar(List<Activity> activities) => MaterialApp(
      theme: AppTheme.light,
      home: ActivityCalendarScreen(initialActivities: activities),
    );

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

    test('staff ยังมีปฏิทินเหมือนเดิม · นิสิตยังไม่มีในเมนู', () {
      expect(navItemsForRole('staff').map((i) => i.id), contains('calendar'));
      expect(navItemsForRole('student').map((i) => i.id), isNot(contains('calendar')));
    });

    testWidgets('sidebar ของแอดมินขึ้นเมนู "ปฏิทินกิจกรรม" จริง', (tester) async {
      _wideScreen(tester);
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

  group('กดวันที่มีกิจกรรม แล้วเห็นรายการของวันนั้น', () {
    testWidgets('แอดมินเห็นชื่อ/เวลา/สถานที่/สถานะ ของกิจกรรมในวันที่กด',
        (tester) async {
      _wideScreen(tester);
      _loginAs('admin');

      await tester.pumpWidget(_calendar([
        _activity(id: 1, name: 'อบรมปฐมพยาบาล', startAt: _at(9, 30)),
        _activity(
          id: 2,
          name: 'ค่ายอาสาพัฒนาชนบท',
          startAt: _at(13, 0),
          location: 'หอประชุมใหญ่',
          approvalStatus: 'approved',
        ),
        _activity(
          id: 3,
          name: 'กิจกรรมวันอื่น',
          startAt: DateTime(_day.year, _day.month, 20, 9, 0),
        ),
      ]));
      await tester.pumpAndSettle();

      final calendar = tester.widget<TableCalendar<Activity>>(
        find.byType(TableCalendar<Activity>),
      );
      expect(calendar.eventLoader!(_day).length, 2,
          reason: 'ตัวโหลดเหตุการณ์ของปฏิทินต้องเห็นกิจกรรมของวันนั้น');

      // กดวันจริงในปฏิทิน
      await tester.tap(find.text('${_day.day}'));
      await tester.pumpAndSettle();

      expect(find.text('อบรมปฐมพยาบาล'), findsOneWidget);
      expect(find.text('ค่ายอาสาพัฒนาชนบท'), findsOneWidget);
      expect(find.textContaining('09:30 น.'), findsOneWidget);
      expect(find.textContaining('ห้องประชุม ชั้น 3'), findsOneWidget);
      expect(find.textContaining('หอประชุมใหญ่'), findsOneWidget);
      // สถานะอนุมัติของทั้งสองรายการ
      expect(find.widgetWithText(StatusChip, 'รออนุมัติ'), findsOneWidget);
      expect(find.widgetWithText(StatusChip, 'อนุมัติแล้ว'), findsOneWidget);
      // กิจกรรมของวันอื่นต้องไม่หลุดมาปน
      expect(find.text('กิจกรรมวันอื่น'), findsNothing);
    });

    testWidgets('วันที่มีกิจกรรมขึ้นจำนวน ไม่ใช่จุดเปล่า ๆ', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');

      await tester.pumpWidget(_calendar([
        _activity(id: 1, startAt: _at(9, 0)),
        _activity(id: 2, startAt: _at(13, 0)),
        _activity(id: 3, startAt: _at(15, 0)),
      ]));
      await tester.pumpAndSettle();

      final calendar = tester.widget<TableCalendar<Activity>>(
        find.byType(TableCalendar<Activity>),
      );
      expect(calendar.calendarBuilders.markerBuilder, isNotNull,
          reason: 'ต้องมีตัววาดเครื่องหมายของตัวเอง ไม่ใช่จุดเริ่มต้นของไลบรารี');
      expect(calendar.eventLoader!(_day).length, 3);
    });

    testWidgets('แอดมินมีทางเข้าไปดู/แก้กิจกรรมจากปฏิทิน', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');

      await tester.pumpWidget(_calendar([_activity(id: 1, startAt: _at(9, 30))]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${_day.day}'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('ดูผู้เข้าร่วม'), findsOneWidget);
      expect(find.byTooltip('แก้ไขกิจกรรม'), findsOneWidget);
    });

    testWidgets('นิสิตไม่มีปุ่มแก้ไขในปฏิทิน', (tester) async {
      _wideScreen(tester);
      _loginAs('student');

      await tester.pumpWidget(_calendar([_activity(id: 1, startAt: _at(9, 30))]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${_day.day}'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('แก้ไขกิจกรรม'), findsNothing);
      expect(find.byTooltip('ดูผู้เข้าร่วม'), findsNothing);
    });

    testWidgets('วันที่ไม่มีกิจกรรมขึ้นข้อความว่างพร้อมวันที่ พ.ศ.', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');

      await tester.pumpWidget(_calendar([_activity(id: 1, startAt: _at(9, 30))]));
      await tester.pumpAndSettle();

      // วันที่ 16 อยู่กลางเดือนเหมือนกัน แต่ไม่มีกิจกรรม
      await tester.tap(find.text('16'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ไม่มีกิจกรรมวันที่ 16'), findsOneWidget);
      expect(find.textContaining('$_thaiYear'), findsWidgets, reason: 'ปีต้องเป็น พ.ศ.');
    });
  });

  group('วันเวลาในรายการเป็น พ.ศ.', () {
    testWidgets('การ์ดบอกวันที่แบบไทย ไม่ใช่ ISO', (tester) async {
      _wideScreen(tester);
      _loginAs('admin');

      await tester.pumpWidget(_calendar([_activity(id: 1, startAt: _at(9, 30))]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${_day.day}'));
      await tester.pumpAndSettle();

      // ปีในการ์ดต้องเป็น พ.ศ. และต้องไม่มีรูปแบบ ISO หลงเหลือ
      expect(find.textContaining('${_day.day} '), findsWidgets);
      expect(find.textContaining('$_thaiYear'), findsWidgets);
      expect(find.textContaining('${_day.year}-'), findsNothing,
          reason: 'ไม่ควรมีวันที่แบบ ISO (ค.ศ.) เหลืออยู่');
    });
  });
}
