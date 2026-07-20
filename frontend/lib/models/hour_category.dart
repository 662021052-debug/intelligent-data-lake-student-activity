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
