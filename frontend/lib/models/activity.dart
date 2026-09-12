class Activity {
  final int? id;
  final String name;
  final String activityType;
  final int? subcategoryId;
  final double hours;
  final bool isRequired;
  final int maxParticipants;
  final DateTime startAt;
  final String location;
  final int? createdBy;
  final String approvalStatus; // pending | approved

  /// เวลาที่ผู้ดูแลกดอนุมัติ (null = ยังไม่อนุมัติ) — คอนโซลใช้นับ "อนุมัติวันนี้"
  final DateTime? approvedAt;
  final int participantCount;

  /// รายการเกณฑ์ที่กิจกรรมนี้นับชั่วโมงให้ — ใช้แนะนำกิจกรรมที่ตรงกับที่นิสิตยังขาด
  final List<int> requirementIds;

  /// ถูก "ซ่อน" แทนการลบ (กิจกรรมที่มีผู้เข้าร่วมแล้ว) — นิสิตไม่เห็น
  /// staff/admin ยังเห็นพร้อม badge และกดเลิกซ่อนได้
  final bool isHidden;

  Activity({
    this.id,
    required this.name,
    required this.activityType,
    this.subcategoryId,
    this.hours = 0,
    this.isRequired = false,
    required this.maxParticipants,
    required this.startAt,
    required this.location,
    this.createdBy,
    this.approvalStatus = 'pending',
    this.approvedAt,
    this.participantCount = 0,
    this.requirementIds = const [],
    this.isHidden = false,
  });

  bool get isFull => participantCount >= maxParticipants;

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        id: json['id'] as int?,
        name: json['name'] as String,
        activityType: json['activity_type'] as String,
        subcategoryId: json['subcategory_id'] as int?,
        hours: (json['hours'] as num?)?.toDouble() ?? 0,
        isRequired: json['is_required'] as bool? ?? false,
        maxParticipants: json['max_participants'] as int,
        startAt: DateTime.parse(json['start_at'] as String),
        location: json['location'] as String,
        createdBy: json['created_by'] as int?,
        approvalStatus: json['approval_status'] as String? ?? 'pending',
        approvedAt: json['approved_at'] == null
            ? null
            : DateTime.parse(json['approved_at'] as String),
        participantCount: json['participant_count'] as int? ?? 0,
        requirementIds: (json['requirement_ids'] as List?)?.cast<int>() ?? const [],
        isHidden: json['is_hidden'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'activity_type': activityType,
        'subcategory_id': subcategoryId,
        'is_required': isRequired,
        'max_participants': maxParticipants,
        'start_at': startAt.toIso8601String(),
        'location': location,
      };
}
