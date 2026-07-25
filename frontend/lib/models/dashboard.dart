// Models for the executive dashboard (Phase 11 Gold-Layer API responses).

class OverviewStats {
  final int totalStudents;
  final int passedCount;
  final double passedPercent;
  final double avgHours;
  final int activityCount;
  final double requiredHoursTotal;

  OverviewStats({
    required this.totalStudents,
    required this.passedCount,
    required this.passedPercent,
    required this.avgHours,
    required this.activityCount,
    required this.requiredHoursTotal,
  });

  factory OverviewStats.fromJson(Map<String, dynamic> json) => OverviewStats(
        totalStudents: json['total_students'] as int,
        passedCount: json['passed_count'] as int,
        passedPercent: (json['passed_percent'] as num).toDouble(),
        avgHours: (json['avg_hours'] as num).toDouble(),
        activityCount: json['activity_count'] as int,
        requiredHoursTotal: (json['required_hours_total'] as num).toDouble(),
      );
}

class CategoryStat {
  final int? categoryKey; // null = "ไม่ระบุหมวด" bucket
  final String categoryName;
  final double requiredHours;
  final double avgEarnedHours;

  CategoryStat({
    required this.categoryKey,
    required this.categoryName,
    required this.requiredHours,
    required this.avgEarnedHours,
  });

  factory CategoryStat.fromJson(Map<String, dynamic> json) => CategoryStat(
        categoryKey: json['category_key'] as int?,
        categoryName: json['category_name'] as String,
        requiredHours: (json['required_hours'] as num).toDouble(),
        avgEarnedHours: (json['avg_earned_hours'] as num).toDouble(),
      );
}

class AtRiskStudent {
  final int studentKey;
  final String studentCode;
  final String fullName;
  final String faculty;
  final int yearLevel;
  final double earnedHours;
  final double requiredHours;
  final double percent;
  final double missingHours;

  AtRiskStudent({
    required this.studentKey,
    required this.studentCode,
    required this.fullName,
    required this.faculty,
    required this.yearLevel,
    required this.earnedHours,
    required this.requiredHours,
    required this.percent,
    required this.missingHours,
  });

  factory AtRiskStudent.fromJson(Map<String, dynamic> json) => AtRiskStudent(
        studentKey: json['student_key'] as int,
        studentCode: json['student_code'] as String,
        fullName: json['full_name'] as String,
        faculty: json['faculty'] as String,
        yearLevel: json['year_level'] as int,
        earnedHours: (json['earned_hours'] as num).toDouble(),
        requiredHours: (json['required_hours'] as num).toDouble(),
        percent: (json['percent'] as num).toDouble(),
        missingHours: (json['missing_hours'] as num).toDouble(),
      );
}

class LowParticipationActivity {
  final int activityKey;
  final String name;
  final String activityType;
  final int maxParticipants;
  final int participantCount;
  final double fillPercent;

  LowParticipationActivity({
    required this.activityKey,
    required this.name,
    required this.activityType,
    required this.maxParticipants,
    required this.participantCount,
    required this.fillPercent,
  });

  factory LowParticipationActivity.fromJson(Map<String, dynamic> json) => LowParticipationActivity(
        activityKey: json['activity_key'] as int,
        name: json['name'] as String,
        activityType: json['activity_type'] as String,
        maxParticipants: json['max_participants'] as int,
        participantCount: json['participant_count'] as int,
        fillPercent: (json['fill_percent'] as num).toDouble(),
      );
}

class FacultyStat {
  final String faculty;
  final int yearLevel;
  final int totalStudents;
  final int passedCount;
  final double passedPercent;

  FacultyStat({
    required this.faculty,
    required this.yearLevel,
    required this.totalStudents,
    required this.passedCount,
    required this.passedPercent,
  });

  factory FacultyStat.fromJson(Map<String, dynamic> json) => FacultyStat(
        faculty: json['faculty'] as String,
        yearLevel: json['year_level'] as int,
        totalStudents: json['total_students'] as int,
        passedCount: json['passed_count'] as int,
        passedPercent: (json['passed_percent'] as num).toDouble(),
      );
}

class TrendPoint {
  final String period;
  final int year;
  final int month;
  final int count;

  TrendPoint({
    required this.period,
    required this.year,
    required this.month,
    required this.count,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        period: json['period'] as String,
        year: json['year'] as int,
        month: json['month'] as int,
        count: json['count'] as int,
      );
}
