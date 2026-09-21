import 'package:activity_tracking_frontend/models/activity.dart';
import 'package:activity_tracking_frontend/models/criteria_set.dart';
import 'package:activity_tracking_frontend/models/hour_category.dart';
import 'package:activity_tracking_frontend/screens/register_activities_screen.dart';
import 'package:activity_tracking_frontend/theme/app_theme.dart';
import 'package:activity_tracking_frontend/utils/format.dart';
import 'package:activity_tracking_frontend/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ตรึงเวลาไว้ทุกเคส ไม่ให้ผลเทสต์ขึ้นกับนาฬิกาของเครื่องที่รัน
final _now = DateTime(2026, 8, 9, 14, 30);

Activity _activity(String name, DateTime startAt, {int taken = 0, int max = 50}) => Activity(
      id: name.hashCode,
      name: name,
      activityType: 'จิตอาสา',
      subcategoryId: 7,
      hours: 4,
      maxParticipants: max,
      startAt: startAt,
      location: 'ห้อง SC101',
      approvalStatus: 'approved',
      participantCount: taken,
    );

void main() {
  group('กิจกรรมที่ยังไม่ผ่านวันจัด', () {
    test('พรุ่งนี้และอนาคตยังไม่ผ่าน', () {
      expect(isUpcomingActivity(_activity('ก', DateTime(2026, 8, 10)), _now), isTrue);
      expect(isUpcomingActivity(_activity('ข', DateTime(2027, 1, 1)), _now), isTrue);
    });

    test('เช้าวันนี้ที่ผ่านมาแล้วยังนับว่าไม่ผ่าน (ตัดที่วัน เหมือนกฎฝั่ง backend)', () {
      expect(isUpcomingActivity(_activity('ค', DateTime(2026, 8, 9, 9, 0)), _now), isTrue);
    });

    test('เมื่อวานถือว่าผ่านไปแล้ว', () {
      expect(isUpcomingActivity(_activity('ง', DateTime(2026, 8, 8, 23, 59)), _now), isFalse);
    });
  });

  group('ลำดับที่นิสิตเห็น', () {
    test('อันที่ใกล้ที่สุดขึ้นก่อน แล้วค่อยตามด้วยอันที่จัดไปแล้ว (เพิ่งจบก่อน)', () {
      final sorted = sortActivitiesForStudent([
        _activity('เดือนหน้า', DateTime(2026, 9, 9)),
        _activity('เมื่อวาน', DateTime(2026, 8, 8)),
        _activity('พรุ่งนี้', DateTime(2026, 8, 10)),
        _activity('เดือนที่แล้ว', DateTime(2026, 7, 9)),
        _activity('วันนี้', DateTime(2026, 8, 9, 18, 0)),
      ], _now);

      expect(sorted.map((a) => a.name).toList(), [
        'วันนี้',
        'พรุ่งนี้',
        'เดือนหน้า',
        'เมื่อวาน',
        'เดือนที่แล้ว',
      ]);
    });

    test('รายการว่างไม่พัง', () {
      expect(sortActivitiesForStudent([], _now), isEmpty);
    });
  });

  group('ป้ายนับถอยหลัง', () {
    test('วันนี้ / พรุ่งนี้ / อีก N วัน / จัดไปแล้ว', () {
      expect(countdownLabel(DateTime(2026, 8, 9, 23, 0), _now), 'วันนี้');
      expect(countdownLabel(DateTime(2026, 8, 9, 8, 0), _now), 'วันนี้');
      expect(countdownLabel(DateTime(2026, 8, 10, 6, 0), _now), 'พรุ่งนี้');
      expect(countdownLabel(DateTime(2026, 8, 16), _now), 'อีก 7 วัน');
      expect(countdownLabel(DateTime(2026, 8, 8, 23, 59), _now), 'จัดไปแล้ว');
    });
  });

  group('วันเวลาบนการ์ด', () {
    test('อ่านเป็นภาษาไทย ปี พ.ศ. ไม่ใช่ ISO', () {
      expect(formatThaiDateTime(DateTime(2026, 12, 1, 9, 0)), '1 ธ.ค. 2569 เวลา 09:00 น.');
      expect(formatThaiDateTime(DateTime(2026, 8, 9, 14, 5)), '9 ส.ค. 2569 เวลา 14:05 น.');
    });
  });

  group('ช่วงเวลากิจกรรม', () {
    test('มีเวลาสิ้นสุดวันเดียวกัน → เวลาเริ่ม–สิ้นสุดในบรรทัดเดียว', () {
      expect(
        formatThaiDateTimeRange(DateTime(2026, 12, 1, 9), DateTime(2026, 12, 1, 12, 30)),
        '1 ธ.ค. 2569 เวลา 09:00–12:30 น.',
      );
    });

    test('ข้ามวัน → แสดงวันที่ทั้งสองปลาย', () {
      expect(
        formatThaiDateTimeRange(DateTime(2026, 12, 1, 9), DateTime(2026, 12, 2, 16)),
        '1 ธ.ค. 2569 เวลา 09:00 น. – 2 ธ.ค. 2569 เวลา 16:00 น.',
      );
    });

    test('ไม่มีเวลาสิ้นสุด → เหมือน formatThaiDateTime เดิม', () {
      final start = DateTime(2026, 12, 1, 9);
      expect(formatThaiDateTimeRange(start, null), formatThaiDateTime(start));
    });
  });

  group('ป้ายที่นั่ง', () {
    test('บอกทั้งจำนวนที่รับและที่ยังเหลือ', () {
      expect(seatsLabel(_activity('ก', _now, taken: 20, max: 50)),
          'สมัครแล้ว 20/50 คน • เหลือ 30 ที่');
    });

    test('เต็มแล้วไม่โชว์ "เหลือ 0 ที่"', () {
      expect(seatsLabel(_activity('ข', _now, taken: 50, max: 50)), 'เต็มแล้ว (รับ 50 คน)');
    });

    test('เกินโควตา (เช่นเช็กอินหน้างานเพิ่ม) ก็ยังบอกว่าเต็ม ไม่ติดลบ', () {
      expect(seatsLabel(_activity('ค', _now, taken: 52, max: 50)), 'เต็มแล้ว (รับ 50 คน)');
    });
  });

  group('ไดอะล็อกยืนยันการสมัคร: บรรทัดเข้าหมวด', () {
    const set = CriteriaSet(
      id: 1,
      code: '2567-regular',
      name: 'เกณฑ์ 2567',
      academicYear: 2567,
      totalRequiredHours: 60,
      groupedBy: 'talent',
      groups: [
        CriteriaGroup(
          key: 'talent:1',
          name: 'TSU Glocal Talent',
          requirements: [
            CriteriaRequirement(
              id: 14,
              name: 'กิจกรรมปฐมนิเทศนิสิต',
              learningUnitName: 'พัฒนาทักษะชีวิต',
            ),
            CriteriaRequirement(id: 16, name: 'การคิด วิจารณญาณ'),
            CriteriaRequirement(id: 17, name: 'รายการ 17'),
            CriteriaRequirement(id: 18, name: 'รายการ 18'),
            CriteriaRequirement(id: 19, name: 'รายการ 19'),
            CriteriaRequirement(id: 20, name: 'รายการ 20'),
          ],
        ),
      ],
    );
    final categories = [
      HourCategory(
        id: 1,
        name: 'ใฝ่เรียนรู้ตลอดชีวิต',
        requiredHours: 30,
        subcategories: [HourSubcategory(id: 7, name: 'กิจกรรม ICT 1', requiredHours: 10)],
      ),
    ];

    Activity activity({List<int> requirementIds = const [], int? subcategoryId}) => Activity(
          id: 1,
          name: 'กิจกรรม',
          activityType: 'อบรม',
          maxParticipants: 10,
          startAt: DateTime(2026, 12, 1),
          location: 'ห้อง A',
          subcategoryId: subcategoryId,
          requirementIds: requirementIds,
        );

    test('ผูกรายการเดียว → ชื่อรายการ + หน่วยการเรียนรู้ บรรทัดเดียว (ไม่ใช่ "-")', () {
      final text = registerCriteriaText(categories, const [set], activity(requirementIds: [14]));
      expect(text, 'เข้าหมวด กิจกรรมปฐมนิเทศนิสิต (หน่วยการเรียนรู้: พัฒนาทักษะชีวิต)');
    });

    test('ผูกหลายรายการ → ขึ้นบรรทัดละรายการ', () {
      final text =
          registerCriteriaText(categories, const [set], activity(requirementIds: [14, 16]));
      expect(text.split('\n'), [
        'เข้าหมวด',
        '• กิจกรรมปฐมนิเทศนิสิต (หน่วยการเรียนรู้: พัฒนาทักษะชีวิต)',
        '• การคิด วิจารณญาณ',
      ]);
    });

    test('รายการเยอะเกินสรุปเป็น "และอีก n รายการ" ไม่ให้ไดอะล็อกสูงล้นจอ', () {
      final text = registerCriteriaText(
        categories,
        const [set],
        activity(requirementIds: [14, 16, 17, 18, 19, 20]),
      );
      final lines = text.split('\n');
      expect(lines.length, 1 + kRegisterCriteriaMaxLines + 1);
      expect(lines.last, 'และอีก 2 รายการ');
    });

    test('กิจกรรมโครงเดิมยังขึ้นหมวดแม่ › หมวดย่อย', () {
      expect(
        registerCriteriaText(categories, const [set], activity(subcategoryId: 7)),
        'เข้าหมวด ใฝ่เรียนรู้ตลอดชีวิต › กิจกรรม ICT 1',
      );
    });

    test('ไม่มีหมวดเลย → ข้อความเข้าใจง่าย ไม่ใช่ "-"', () {
      final text = registerCriteriaText(categories, const [set], activity());
      expect(text, 'ยังไม่กำหนดหมวด');
      expect(text, isNot('-'));
    });

    testWidgets('จอแคบ 320px: ไดอะล็อกที่มีหลายรายการไม่ล้น', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmAction(
              context,
              title: 'ยืนยันการสมัคร',
              message: 'สมัครเข้าร่วม "กิจกรรมชื่อยาว ๆ ยาว ๆ ยาว ๆ ยาว ๆ"\n\nได้ 4 ชั่วโมง\n'
                  '${registerCriteriaText(categories, const [set], activity(requirementIds: [14, 16, 17, 18, 19, 20]))}',
            ),
            child: const Text('เปิด'),
          ),
        ),
      ));
      await tester.tap(find.text('เปิด'));
      await tester.pumpAndSettle();

      expect(find.textContaining('และอีก 2 รายการ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
