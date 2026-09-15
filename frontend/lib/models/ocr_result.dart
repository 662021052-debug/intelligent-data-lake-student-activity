// Silver-layer OCR result for one evidence file (Phase 13–14 API response).

class OcrResult {
  final int id;
  final int rawFileId;
  final int? participationId;
  final String extractedText;
  final double ocrConfidence;
  final double matchScore;
  final String decision; // auto_approved | needs_review | flagged
  final bool isDuplicate;
  final DateTime processedAt;

  /// การเข้าร่วมที่ไฟล์นี้ซ้ำด้วย — null ถ้าไม่ซ้ำ หรือเป็นผล OCR ก่อนเฟส 1.2
  final int? duplicateOfParticipationId;

  /// cross_student | same_student_reuse | matches_rejected (null เหมือนข้างบน)
  final String? duplicateReason;

  /// exact = ไฟล์เดียวกันเป๊ะ (checksum) · near = ภาพคล้ายกันมาก (pHash) · null = ไม่ซ้ำ/ผลรุ่นเก่า
  final String? matchKind;

  /// ประเภทของไฟล์ที่ประมวลผล: certificate | photo | other (backend ส่ง certificate แทน null)
  final String? evidenceKind;

  // บริบทของใบต้นทาง (backend คำนวณตอนอ่าน) — null ถ้าไม่ซ้ำ / ผลรุ่นเก่า / ผู้ใช้เป็นนิสิต
  final String? duplicateOfStudentName;
  final String? duplicateOfStudentCode;
  final String? duplicateOfActivityName;
  final String? duplicateOfEvidenceStatus; // pending | approved | rejected

  /// ผู้ใช้คนนี้เปิดหน้าตรวจของใบต้นทางได้ไหม (staff เฉพาะกิจกรรมของตัวเอง)
  final bool duplicateOfViewable;

  OcrResult({
    required this.id,
    required this.rawFileId,
    required this.participationId,
    required this.extractedText,
    required this.ocrConfidence,
    required this.matchScore,
    required this.decision,
    required this.isDuplicate,
    required this.processedAt,
    this.duplicateOfParticipationId,
    this.duplicateReason,
    this.matchKind,
    this.evidenceKind,
    this.duplicateOfStudentName,
    this.duplicateOfStudentCode,
    this.duplicateOfActivityName,
    this.duplicateOfEvidenceStatus,
    this.duplicateOfViewable = false,
  });

  factory OcrResult.fromJson(Map<String, dynamic> json) => OcrResult(
        id: json['id'] as int,
        rawFileId: json['raw_file_id'] as int,
        participationId: json['participation_id'] as int?,
        extractedText: json['extracted_text'] as String? ?? '',
        ocrConfidence: (json['ocr_confidence'] as num).toDouble(),
        matchScore: (json['match_score'] as num).toDouble(),
        decision: json['decision'] as String,
        isDuplicate: json['is_duplicate'] as bool? ?? false,
        processedAt: DateTime.parse(json['processed_at'] as String),
        duplicateOfParticipationId: json['duplicate_of_participation_id'] as int?,
        duplicateReason: json['duplicate_reason'] as String?,
        matchKind: json['match_kind'] as String?,
        evidenceKind: json['evidence_kind'] as String?,
        duplicateOfStudentName: json['duplicate_of_student_name'] as String?,
        duplicateOfStudentCode: json['duplicate_of_student_code'] as String?,
        duplicateOfActivityName: json['duplicate_of_activity_name'] as String?,
        duplicateOfEvidenceStatus: json['duplicate_of_evidence_status'] as String?,
        duplicateOfViewable: json['duplicate_of_viewable'] as bool? ?? false,
      );
}
