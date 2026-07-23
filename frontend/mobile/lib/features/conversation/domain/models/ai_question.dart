enum AiResponseMode { voice, emoji, color, picture, text }

// 다음 질문 생성 요청 계약
final class NextQuestionRequest {
  const NextQuestionRequest({
    this.basisAnalysisId,
    this.previousAnswerMessageId,
    this.preferredResponseModes = const [
      AiResponseMode.voice,
      AiResponseMode.emoji,
      AiResponseMode.text,
    ],
  });

  final int? basisAnalysisId;
  final int? previousAnswerMessageId;
  final List<AiResponseMode> preferredResponseModes;

  Map<String, dynamic> toJson() => {
    'basisAnalysisId': ?basisAnalysisId,
    'previousAnswerMessageId': ?previousAnswerMessageId,
    'preferredResponseModes': preferredResponseModes
        .map((mode) => mode.name.toUpperCase())
        .toList(growable: false),
  };
}

// 질문 선택지 응답 모델
final class AiQuestionOption {
  const AiQuestionOption({
    required this.optionId,
    required this.type,
    required this.label,
    required this.value,
    this.emoji,
  });

  factory AiQuestionOption.fromJson(Map<String, dynamic> json) =>
      AiQuestionOption(
        optionId: json['optionId'].toString(),
        type: json['type'] as String,
        label: json['label'] as String,
        value: json['value'] as String,
        emoji: json['emoji'] as String?,
      );

  final String optionId;
  final String type;
  final String label;
  final String value;
  final String? emoji;
}

// 백엔드가 반환한 AI 질문 모델
final class AiQuestion {
  const AiQuestion({
    required this.messageId,
    required this.conversationId,
    required this.sequence,
    required this.text,
    required this.options,
    required this.ttsAvailable,
    required this.createdAt,
  });

  factory AiQuestion.fromJson(Map<String, dynamic> json) => AiQuestion(
    messageId: json['messageId'] as int,
    conversationId: json['conversationId'] as int,
    sequence: json['sequence'] as int,
    text: json['text'] as String,
    options: (json['options'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              AiQuestionOption.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
    ttsAvailable: json['ttsAvailable'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final int messageId;
  final int conversationId;
  final int sequence;
  final String text;
  final List<AiQuestionOption> options;
  final bool ttsAvailable;
  final DateTime createdAt;
}
