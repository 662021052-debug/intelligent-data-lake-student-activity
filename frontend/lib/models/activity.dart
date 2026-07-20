class Activity {
  final int? id;
  final String name;
  final String activityType;
  final String hourCategory;
  final bool isRequired;
  final int maxParticipants;
  final DateTime startAt;
  final String location;
  final int? createdBy;
  final String approvalStatus; // pending | approved
  final int participantCount;

  Activity({
    this.id,
    required this.name,
    required this.activityType,
    required this.hourCategory,
    this.isRequired = false,
    required this.maxParticipants,
    required this.startAt,
    required this.location,
    this.createdBy,
    this.approvalStatus = 'pending',
    this.participantCount = 0,
  });

  bool get isFull => participantCount >= maxParticipants;

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        id: json['id'] as int?,
        name: json['name'] as String,
        activityType: json['activity_type'] as String,
        hourCategory: json['hour_category'] as String,
        isRequired: json['is_required'] as bool? ?? false,
        maxParticipants: json['max_participants'] as int,
        startAt: DateTime.parse(json['start_at'] as String),
        location: json['location'] as String,
        createdBy: json['created_by'] as int?,
        approvalStatus: json['approval_status'] as String? ?? 'pending',
        participantCount: json['participant_count'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'activity_type': activityType,
        'hour_category': hourCategory,
        'is_required': isRequired,
        'max_participants': maxParticipants,
        'start_at': startAt.toIso8601String(),
        'location': location,
      };
}
