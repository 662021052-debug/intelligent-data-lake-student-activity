import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/hour_summary.dart';
import 'package:activity_tracking_frontend/models/participation.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/app_card.dart';
import 'package:activity_tracking_frontend/widgets/student_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

HourSubcategorySummary _item(int id, String name, double earned, double required) =>
    HourSubcategorySummary(
      id: id,
      name: name,
      earnedHours: earned,
      requiredHours: required,
      completed: earned >= required,
    );

HourCategorySummary _talent(
  int id,
  String name,
  List<HourSubcategorySummary> items,
) {
  final earned = items.fold<double>(0, (s, i) => s + i.earnedHours);
  final required = items.fold<double>(0, (s, i) => s + i.requiredHours);
  return HourCategorySummary(
    id: id,
    name: name,
    earnedHours: earned,
    requiredHours: required,
    completed: items.every((i) => i.completed),
    subcategories: items,
  );
}

Activity _activity({
  required int id,
  required String name,
  required DateTime startAt,
  List<int> requirementIds = const [],
  int participantCount = 0,
  int maxParticipants = 100,
  String approvalStatus = 'approved',
  bool isHidden = false,
  double hours = 4,
}) =>
    Activity(
      id: id,
      name: name,
      activityType: 'อบรม',
      startAt: startAt,
      location: 'หอประชุม',
      maxParticipants: maxParticipants,
      participantCount: participantCount,
      approvalStatus: approvalStatus,
      isHidden: isHidden,
      hours: hours,
      requirementIds: requirementIds,
    );

Participation _participation(int activityId) =>
    Participation(id: activityId, studentId: 1, activityId: activityId);

final _now = DateTime(2026, 9, 12);

void main() {
  group('StudentProgressSummary', () {
    test('ชั่วโมงเกินเป้าของรายการหนึ่งไม่ไปชดเชยรายการที่ยังขาด', () {
      // เก็บ 20 ชม. ในรายการที่ต้องการ 10 แล้วอีกรายการยังเป็น 0 — รวมดิบได้ 20/20
      // แต่ที่นับเข้าเกณฑ์จริงคือ 10/20 และยังไม่ครบ (กติกาเดียวกับ app/completion.py)
      final progress = StudentProgressSummary.from([
        _talent(1, 'Talent A', [_item(10, 'เกิน', 20, 10), _item(11, 'ขาด', 0, 10)]),
      ]);

      expect(progress.earned, 10);
      expect(progress.required_, 20);
      expect(progress.percent, 50);
      expect(progress.completed, isFalse);
      expect(progress.gaps.map((g) => g.id), [11]);
    });

    test('ครบทุกรายการ = 100% และถือว่าครบเกณฑ์', () {
      final progress = StudentProgressSummary.from([
        _talent(1, 'Talent A', [_item(10, 'ก', 4, 4)]),
        _talent(2, 'Talent B', [_item(11, 'ข', 6, 6)]),
      ]);

      expect(progress.percent, 100);
      expect(progress.completed, isTrue);
      expect(progress.gaps, isEmpty);
    });

    test('ยังไม่มีเกณฑ์ให้วัด ไม่นับว่าครบ', () {
      const empty = <HourCategorySummary>[];
      final progress = StudentProgressSummary.from(empty);

      expect(progress.percent, 0);
      expect(progress.completed, isFalse);
    });

    test('gaps เรียงจากรายการที่ขาดมากที่สุด', () {
      final progress = StudentProgressSummary.from([
        _talent(1, 'Talent A', [
          _item(10, 'ขาด 2', 1, 3),
          _item(11, 'ขาด 9', 1, 10),
          _item(12, 'ครบ', 5, 5),
        ]),
      ]);

      expect(progress.gaps.map((g) => g.id), [11, 10]);
      expect(progress.gapItemIds, {10, 11});
    });
  });

  group('upcomingRegistered', () {
    test('เอาเฉพาะกิจกรรมที่สมัครไว้และยังไม่ถึงวัน เรียงใกล้สุดก่อน', () {
      final activities = [
        _activity(id: 1, name: 'ผ่านไปแล้ว', startAt: _now.subtract(const Duration(days: 3))),
        _activity(id: 2, name: 'อีกเดือน', startAt: _now.add(const Duration(days: 30))),
        _activity(id: 3, name: 'พรุ่งนี้', startAt: _now.add(const Duration(days: 1))),
        _activity(id: 4, name: 'ไม่ได้สมัคร', startAt: _now.add(const Duration(days: 2))),
      ];
      final mine = [_participation(1), _participation(2), _participation(3)];

      final upcoming = upcomingRegistered(mine, activities, now: _now);

      expect(upcoming.map((a) => a.name), ['พรุ่งนี้', 'อีกเดือน']);
    });
  });

  group('recommendedActivities', () {
    List<Activity> pool() => [
          _activity(
            id: 1,
            name: 'ตรงกับที่ขาด (ไกล)',
            startAt: _now.add(const Duration(days: 20)),
            requirementIds: [16],
          ),
          _activity(
            id: 2,
            name: 'ไม่ตรง (ใกล้สุด)',
            startAt: _now.add(const Duration(days: 1)),
            requirementIds: [99],
          ),
          _activity(
            id: 3,
            name: 'เต็มแล้ว',
            startAt: _now.add(const Duration(days: 2)),
            requirementIds: [16],
            participantCount: 100,
            maxParticipants: 100,
          ),
          _activity(
            id: 4,
            name: 'ผ่านไปแล้ว',
            startAt: _now.subtract(const Duration(days: 1)),
            requirementIds: [16],
          ),
          _activity(
            id: 5,
            name: 'ยังไม่อนุมัติ',
            startAt: _now.add(const Duration(days: 3)),
            requirementIds: [16],
            approvalStatus: 'pending',
          ),
          _activity(
            id: 6,
            name: 'ถูกซ่อน',
            startAt: _now.add(const Duration(days: 4)),
            requirementIds: [16],
            isHidden: true,
          ),
          _activity(
            id: 7,
            name: 'สมัครไว้แล้ว',
            startAt: _now.add(const Duration(days: 5)),
            requirementIds: [16],
          ),
        ];

    test('แนะนำเฉพาะที่นับเข้ารายการที่ยังขาด และข้ามตัวที่สมัคร/เต็ม/ซ่อน/ยังไม่อนุมัติ',
        () {
      final picked = recommendedActivities(
        activities: pool(),
        participations: [_participation(7)],
        gapItemIds: {16},
        now: _now,
      );

      expect(picked.map((a) => a.name), ['ตรงกับที่ขาด (ไกล)']);
    });

    test('ไม่มีอันไหนตรงรายการที่ขาด ใช้ที่ใกล้ถึงที่สุดแทน ไม่ปล่อยการ์ดว่าง', () {
      final picked = recommendedActivities(
        activities: pool(),
        participations: const [],
        gapItemIds: {12345}, // ไม่มีกิจกรรมไหนตรงเลย
        now: _now,
      );

      expect(picked, isNotEmpty);
      expect(picked.first.name, 'ไม่ตรง (ใกล้สุด)');
    });

    test('ไม่มีกิจกรรมเปิดรับเลยก็คืนลิสต์ว่าง ไม่พัง', () {
      final picked = recommendedActivities(
        activities: [
          _activity(id: 1, name: 'ผ่านแล้ว', startAt: _now.subtract(const Duration(days: 1))),
        ],
        participations: const [],
        gapItemIds: {16},
        now: _now,
      );

      expect(picked, isEmpty);
    });
  });

  group('TalentProgressCard', () {
    testWidgets('หนึ่งแถบต่อหนึ่ง Talent พร้อมตัวเลขและสีตามความคืบหน้า', (tester) async {
      await tester.pumpWidget(_wrap(TalentProgressCard(
        talents: [
          _talent(1, 'TSU Glocal Talent', [_item(10, 'ก', 18, 30)]),
          _talent(2, 'TSU Communication', [_item(11, 'ข', 10, 10)]),
        ],
        onOpenDetail: () {},
      )));

      expect(find.text('ชั่วโมงตาม Talent / PLO'), findsOneWidget);
      expect(find.text('TSU Glocal Talent'), findsOneWidget);
      expect(find.text('18/30'), findsOneWidget);
      // ครบแล้วติดเครื่องหมายถูกตาม mockup
      expect(find.text('10/10 ✓'), findsOneWidget);
      expect(find.byType(ProgressRow), findsNWidgets(2));

      final bars = tester.widgetList<ProgressRow>(find.byType(ProgressRow)).toList();
      expect(ProgressRow.barColor(bars[0].progress), AppColors.blue, reason: '60%');
      expect(
        ProgressRow.barColor(bars[1].progress),
        StatusPalette.approved.accent,
        reason: 'ครบ 100%',
      );
    });

    testWidgets('ปุ่มใบประมวลผลกิจกรรมยังอยู่และกดได้', (tester) async {
      var opened = false;
      await tester.pumpWidget(_wrap(TalentProgressCard(
        talents: [_talent(1, 'Talent', [_item(10, 'ก', 1, 2)])],
        onOpenDetail: () => opened = true,
      )));

      await tester.tap(find.widgetWithText(FilledButton, 'ใบประมวลผลกิจกรรม'));
      expect(opened, isTrue);
    });

    testWidgets('ยังไม่มีชั่วโมงก็บอกตรง ๆ ไม่ใช่การ์ดว่าง', (tester) async {
      await tester.pumpWidget(_wrap(const TalentProgressCard(talents: [])));
      expect(find.textContaining('ยังไม่มีชั่วโมงสะสม'), findsOneWidget);
    });
  });

  group('SuggestedActivitiesCard', () {
    testWidgets('แสดงชื่อกิจกรรม ชั่วโมง และวันที่', (tester) async {
      await tester.pumpWidget(_wrap(SuggestedActivitiesCard(
        activities: [
          _activity(
            id: 1,
            name: 'ค่ายอาสาพัฒนาชุมชน 5',
            startAt: DateTime(2026, 9, 18),
            hours: 12,
          ),
        ],
        onSeeAll: () {},
      )));

      expect(find.text('แนะนำให้เข้าร่วม'), findsOneWidget);
      expect(find.text('เติมรายการที่ยังขาด'), findsOneWidget);
      expect(find.text('ค่ายอาสาพัฒนาชุมชน 5'), findsOneWidget);
      expect(find.text('12 ชม.'), findsOneWidget);
    });

    testWidgets('ครบเกณฑ์แล้วเปลี่ยนคำโปรย ไม่บอกว่ายังขาด', (tester) async {
      await tester.pumpWidget(_wrap(SuggestedActivitiesCard(
        activities: [_activity(id: 1, name: 'กิจกรรม', startAt: DateTime(2026, 10, 1))],
        matchedGaps: false,
      )));

      expect(find.textContaining('ครบเกณฑ์แล้ว'), findsOneWidget);
      expect(find.text('เติมรายการที่ยังขาด'), findsNothing);
    });

    testWidgets('ไม่มีกิจกรรมให้แนะนำก็ขึ้นสถานะว่าง', (tester) async {
      await tester.pumpWidget(_wrap(const SuggestedActivitiesCard(activities: [])));
      expect(find.textContaining('ยังไม่มีกิจกรรมเปิดรับ'), findsOneWidget);
    });
  });
}
