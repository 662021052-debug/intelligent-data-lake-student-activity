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
      );
}
