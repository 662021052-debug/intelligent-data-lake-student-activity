class HourSubcategorySummary {
  final int id;
  final String name;
  final double requiredHours;
  final double earnedHours;
  final bool completed;

  HourSubcategorySummary({
    required this.id,
    required this.name,
    required this.requiredHours,
    required this.earnedHours,
    required this.completed,
  });

  factory HourSubcategorySummary.fromJson(Map<String, dynamic> json) => HourSubcategorySummary(
        id: json['id'] as int,
        name: json['name'] as String,
        requiredHours: (json['required_hours'] as num).toDouble(),
        earnedHours: (json['earned_hours'] as num).toDouble(),
        completed: json['completed'] as bool,
      );
}

class HourCategorySummary {
  final int id;
  final String name;
  final double requiredHours;
  final double earnedHours;
  final bool completed;
  final List<HourSubcategorySummary> subcategories;

  HourCategorySummary({
    required this.id,
    required this.name,
    required this.requiredHours,
    required this.earnedHours,
    required this.completed,
    required this.subcategories,
  });

  factory HourCategorySummary.fromJson(Map<String, dynamic> json) => HourCategorySummary(
        id: json['id'] as int,
        name: json['name'] as String,
        requiredHours: (json['required_hours'] as num).toDouble(),
        earnedHours: (json['earned_hours'] as num).toDouble(),
        completed: json['completed'] as bool,
        subcategories: (json['subcategories'] as List)
            .map((e) => HourSubcategorySummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
