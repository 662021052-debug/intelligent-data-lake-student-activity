import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/widgets/activity_detail_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _activity({
  List<int> requirementIds = const [4],
  int taken = 10,
  int max = 50,
  bool isRequired = false,
}) =>
    Activity(
      id: 1,
      name: 'ค่ายอาสาพัฒนาชุมชน ครั้งที่ 3/2569',
      activityType: 'จิตอาสา',
      subcategoryId: 7,
      hours: 4,
      maxParticipants: max,
      startAt: DateTime(2026, 11, 20, 9, 0),
      location: 'ลานกิจกรรม',
      approvalStatus: 'approved',
      participantCount: taken,
      isRequired: isRequired,
      requirementIds: requirementIds,
    );

// `CriteriaSet.requirements` เป็น getter ที่ยุบมาจาก groups — ต้องสร้างผ่านกลุ่ม
const List<CriteriaSet> _criteriaSets = [
  CriteriaSet(
    id: 1,
    code: '2567-regular',
    name: 'เกณฑ์ 2567 หลักสูตรปกติ',
    academicYear: 2567,
    totalRequiredHours: 60,
    groups: [
      CriteriaGroup(
        key: 'talent:1',
        name: 'TSU Glocal Talent',
        subtitle: 'PLO 1',
        requirements: [
          CriteriaRequirement(
            id: 4,
            name: 'กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์)',
            requiredHours: 10,
            learningUnitName: 'TSU รับใช้สังคม',
          ),
          CriteriaRequirement(
            id: 9,
            name: 'กิจกรรมปฐมนิเทศนิสิต',
            requiredHours: 4,
            isMandatory: true,
            learningUnitName: 'ใฝ่เรียนรู้ตลอดชีวิต',
          ),
        ],
      ),
    ],
  ),
];

Future<ActivityDetailAction?> _open(
  WidgetTester tester, {
  required Activity activity,
  bool registered = false,
  String? evidenceStatus,
  bool closed = false,
  String? categoryProgress,
  String? countdown = 'อีก 5 วัน',
}) async {
  ActivityDetailAction? result;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showDialog<ActivityDetailAction>(
                context: context,
                builder: (_) => ActivityDetailDialog(
                  activity: activity,
                  categories: const [],
                  criteriaSets: _criteriaSets,
                  registered: registered,
                  evidenceStatus: evidenceStatus,
                  closed: closed,
                  categoryProgress: categoryProgress,
                  countdown: countdown,
                ),
              );
            },
            child: const Text('เปิด'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('เปิด'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('หน้ารายละเอียดกิจกรรมก่อนสมัคร', () {
    testWidgets('บอกครบทุกอย่างที่ต้องรู้ก่อนกดสมัคร', (tester) async {
      await _open(tester, activity: _activity());

      expect(find.text('ค่ายอาสาพัฒนาชุมชน ครั้งที่ 3/2569'), findsOneWidget);
      expect(find.text('จิตอาสา'), findsOneWidget);
      expect(find.text('อีก 5 วัน'), findsOneWidget);
      // วันเวลาเป็นเวลาไทยตาม formatThaiDateTime (พ.ศ.)
      expect(find.textContaining('20 พ.ย. 2569'), findsOneWidget);
      expect(find.text('ลานกิจกรรม'), findsOneWidget);
      expect(find.text('4 ชั่วโมง'), findsOneWidget);
      expect(find.textContaining('รับ 10/50 คน'), findsOneWidget);
      expect(find.textContaining('เหลือ 40 ที่'), findsOneWidget);
      // รายการเกณฑ์ที่นับเข้า + หน่วยการเรียนรู้
      expect(find.text('กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์)'), findsOneWidget);
      expect(find.text('หน่วยการเรียนรู้: TSU รับใช้สังคม'), findsOneWidget);
      expect(find.text('เลือก'), findsOneWidget);
    });

    testWidgets('กิจกรรมที่ผูกหลายรายการเกณฑ์ แสดงครบทุกรายการ', (tester) async {
      await _open(tester, activity: _activity(requirementIds: [4, 9]));

      expect(find.text('กลุ่ม TSU Good (จิตอาสา/บำเพ็ญประโยชน์)'), findsOneWidget);
      expect(find.text('กิจกรรมปฐมนิเทศนิสิต'), findsOneWidget);
      expect(find.text('บังคับ'), findsOneWidget);
      expect(find.text('เลือก'), findsOneWidget);
    });

    testWidgets('กดสมัครแล้วคืน action ให้หน้าที่เรียก (ไดอะล็อกไม่ยิง API เอง)',
        (tester) async {
      ActivityDetailAction? captured;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDialog<ActivityDetailAction>(
                    context: context,
                    builder: (_) => ActivityDetailDialog(
                      activity: _activity(),
                      categories: const [],
                      criteriaSets: _criteriaSets,
                    ),
                  );
                },
                child: const Text('เปิด'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('เปิด'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'สมัครเข้าร่วม'));
      await tester.pumpAndSettle();

      expect(captured, ActivityDetailAction.register);
    });

    testWidgets('สมัครไว้แล้ว: เห็นสถานะหลักฐาน + ปุ่มยกเลิก ไม่มีปุ่มสมัคร', (tester) async {
      await _open(
        tester,
        activity: _activity(),
        registered: true,
        evidenceStatus: 'pending',
      );

      expect(find.text('ยกเลิกการสมัคร'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'สมัครเข้าร่วม'), findsNothing);
    });

    testWidgets('เต็มแล้ว: ไม่มีปุ่มสมัครให้กด', (tester) async {
      await _open(tester, activity: _activity(taken: 50, max: 50));

      expect(find.text('เต็มแล้ว'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'สมัครเข้าร่วม'), findsNothing);
    });

    testWidgets('ปิดรับแล้ว: ไม่มีปุ่มสมัครให้กด', (tester) async {
      await _open(tester, activity: _activity(), closed: true);

      expect(find.text('ปิดรับสมัครแล้ว'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'สมัครเข้าร่วม'), findsNothing);
    });

    testWidgets('บอกด้วยว่าหมวดนี้ยังขาดอีกเท่าไร', (tester) async {
      await _open(
        tester,
        activity: _activity(),
        categoryProgress: 'หมวดนี้คุณมี 4/12 ชม. — ยังขาดอีก 8 ชม.',
      );

      expect(find.text('หมวดนี้คุณมี 4/12 ชม. — ยังขาดอีก 8 ชม.'), findsOneWidget);
    });

    testWidgets('จอแคบ 360: ไม่มีส่วนไหนล้นจอ', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _open(tester, activity: _activity(requirementIds: [4, 9]));

      expect(tester.takeException(), isNull);
    });
  });
}
