// Chatbot answer (Phase 16–18 API response from POST /chatbot/ask).

class ChatSource {
  final String source;
  final int chunkIndex;
  final String content;
  final double score;

  ChatSource({
    required this.source,
    required this.chunkIndex,
    required this.content,
    required this.score,
  });

  factory ChatSource.fromJson(Map<String, dynamic> json) => ChatSource(
        source: json['source'] as String? ?? '',
        chunkIndex: json['chunk_index'] as int? ?? 0,
        content: json['content'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble() ?? 0,
      );
}

class ChatResponse {
  final String intent;
  final String answer;
  final List<ChatSource> sources;

  ChatResponse({
    required this.intent,
    required this.answer,
    required this.sources,
  });

  /// True when the answer lists activities the student could register for.
  bool get referencesActivities =>
      intent == 'open_activities' || intent == 'required' || intent == 'recommend';

  factory ChatResponse.fromJson(Map<String, dynamic> json) => ChatResponse(
        intent: json['intent'] as String? ?? '',
        answer: json['answer'] as String? ?? '',
        sources: (json['sources'] as List<dynamic>? ?? [])
            .map((e) => ChatSource.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
