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
      );
}
