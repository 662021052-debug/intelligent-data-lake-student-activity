class Participation {
  final int? id;
  final int studentId;
  final int activityId;
  final DateTime? checkInTime;
  final double hoursEarned;
  final String evidenceStatus; // pending | approved | rejected
  final String? activityName;
  final String? studentName;
  final String? studentCode; // รหัสนิสิต ไม่ใช่ id ในฐาน
  final bool hasEvidence;
  final DateTime? evidenceUploadedAt;
  // Silver-layer OCR summary, folded into the participation payload.
  final bool hasOcr;
  final String? ocrDecision; // auto_approved | needs_review | flagged
  final double? ocrMatchScore;
  final double? ocrConfidence;

  Participation({
    this.id,
    required this.studentId,
    required this.activityId,
    this.checkInTime,
    this.hoursEarned = 0,
    this.evidenceStatus = 'pending',
    this.activityName,
    this.studentName,
    this.studentCode,
    this.hasEvidence = false,
    this.evidenceUploadedAt,
    this.hasOcr = false,
    this.ocrDecision,
    this.ocrMatchScore,
    this.ocrConfidence,
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
        activityName: json['activity_name'] as String?,
        studentName: json['student_name'] as String?,
        studentCode: json['student_code'] as String?,
        hasEvidence: json['has_evidence'] as bool? ?? false,
        evidenceUploadedAt: json['evidence_uploaded_at'] == null
            ? null
            : DateTime.parse(json['evidence_uploaded_at'] as String),
        hasOcr: json['has_ocr'] as bool? ?? false,
        ocrDecision: json['ocr_decision'] as String?,
        ocrMatchScore: (json['ocr_match_score'] as num?)?.toDouble(),
        ocrConfidence: (json['ocr_confidence'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'student_id': studentId,
        'activity_id': activityId,
        'check_in_time': checkInTime?.toIso8601String(),
        'hours_earned': hoursEarned,
        'evidence_status': evidenceStatus,
      };
}
