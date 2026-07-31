/// ชื่อเต็มของหมวดชั่วโมงในรูป "หมวดแม่ › หมวดย่อย" เช่น "ใฝ่เรียนรู้ตลอดชีวิต › กิจกรรม ICT 1"
///
/// ใช้ร่วมกันทุกหน้าที่ต้องบอกว่ากิจกรรมนับชั่วโมงเข้าหมวดไหน
/// (ตารางกิจกรรมของเจ้าหน้าที่ และการ์ด/ดialog สมัครของนิสิต)
String subcategoryPath(List<HourCategory> categories, int? subcategoryId) {
  if (subcategoryId == null) return '-';
  for (final category in categories) {
    for (final sub in category.subcategories) {
      if (sub.id == subcategoryId) return '${category.name} › ${sub.name}';
    }
  }
  return '-';
}

/// หมวดแม่ของหมวดย่อยนี้ (null ถ้าไม่พบ) — ใช้เทียบกับสรุปชั่วโมงของนิสิต
HourCategory? parentCategoryOf(List<HourCategory> categories, int? subcategoryId) {
  if (subcategoryId == null) return null;
  for (final category in categories) {
    for (final sub in category.subcategories) {
      if (sub.id == subcategoryId) return category;
    }
  }
  return null;
}

class HourSubcategory {
  final int id;
  final String name;
  final double requiredHours;

  HourSubcategory({
    required this.id,
    required this.name,
    required this.requiredHours,
  });

  factory HourSubcategory.fromJson(Map<String, dynamic> json) => HourSubcategory(
        id: json['id'] as int,
        name: json['name'] as String,
        requiredHours: (json['required_hours'] as num).toDouble(),
      );
}

class HourCategory {
  final int id;
  final String name;
  final double requiredHours;
  final List<HourSubcategory> subcategories;

  HourCategory({
    required this.id,
    required this.name,
    required this.requiredHours,
    required this.subcategories,
  });

  factory HourCategory.fromJson(Map<String, dynamic> json) => HourCategory(
        id: json['id'] as int,
        name: json['name'] as String,
        requiredHours: (json['required_hours'] as num).toDouble(),
        subcategories: (json['subcategories'] as List)
            .map((e) => HourSubcategory.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
