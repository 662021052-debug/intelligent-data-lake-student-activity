import 'package:activity_tracking_frontend/models/hour_category.dart';
import 'package:flutter_test/flutter_test.dart';

HourCategory _category(int id, String name, List<HourSubcategory> subs) => HourCategory(
      id: id,
      name: name,
      requiredHours: 12,
      subcategories: subs,
    );

void main() {
  final categories = [
    _category(1, 'ใฝ่เรียนรู้ตลอดชีวิต', [
      HourSubcategory(id: 11, name: 'กิจกรรม ICT 1', requiredHours: 6),
      HourSubcategory(id: 12, name: 'กิจกรรมภาษาอังกฤษ', requiredHours: 6),
    ]),
    _category(2, 'จิตอาสาและความรับผิดชอบต่อสังคม', [
      HourSubcategory(id: 21, name: 'กิจกรรมบำเพ็ญประโยชน์', requiredHours: 12),
    ]),
  ];

  group('subcategoryPath', () {
    test('บอกหมวดเต็ม "หมวดแม่ › หมวดย่อย" ให้นิสิตรู้ก่อนกดสมัคร', () {
      expect(subcategoryPath(categories, 11), 'ใฝ่เรียนรู้ตลอดชีวิต › กิจกรรม ICT 1');
      expect(subcategoryPath(categories, 21), 'จิตอาสาและความรับผิดชอบต่อสังคม › กิจกรรมบำเพ็ญประโยชน์');
    });

    test('กิจกรรมที่ยังไม่ผูกหมวด หรือหมวดที่ไม่รู้จัก แสดง "-" ไม่ใช่ id ดิบ', () {
      expect(subcategoryPath(categories, null), '-');
      expect(subcategoryPath(categories, 999), '-');
      expect(subcategoryPath(const [], 11), '-');
    });
  });

  group('parentCategoryOf', () {
    test('หาหมวดแม่เพื่อเทียบกับชั่วโมงสะสมของนิสิต', () {
      expect(parentCategoryOf(categories, 12)?.id, 1);
      expect(parentCategoryOf(categories, 21)?.name, 'จิตอาสาและความรับผิดชอบต่อสังคม');
    });

    test('ไม่พบหมวดคืน null (หน้าจอจะไม่แสดงบรรทัดความคืบหน้า)', () {
      expect(parentCategoryOf(categories, null), isNull);
      expect(parentCategoryOf(categories, 999), isNull);
    });
  });
}
