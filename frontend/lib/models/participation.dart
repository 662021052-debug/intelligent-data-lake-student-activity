class Participation {
  final int? id;
  final int studentId;
  final int activityId;
  final DateTime? checkInTime;
  final double hoursEarned;
  final String evidenceStatus; // pending | approved | rejected

  Participation({
    this.id,
    required this.studentId,
    required this.activityId,
    this.checkInTime,
    this.hoursEarned = 0,
    this.evidenceStatus = 'pending',
  });

  factory Participation.fromJson(Map<String, dynamic> json) => Participation(
        id: json['id'] as int?,
        studentId: json['student_id'] as int,
        activityId: json['activity_id'] as int,
        checkInTime: json['check_in_time'] == null
            ? null
            : DateTime.parse(json['check_in_time'] as String),
        hoursEarned: (json['hours_earned'] as num?)?.toDouble() ?? 0,
        evidenceStatus: json['evidence_status'] as String? ?? 'pending',
      );

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'activity_id': activityId,
        'check_in_time': checkInTime?.toIso8601String(),
        'hours_earned': hoursEarned,
        'evidence_status': evidenceStatus,
      };
}
