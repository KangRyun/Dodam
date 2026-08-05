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

/// 아이가 되묻기에 말로 그만하겠다고 확인한 대상 (S15P11B209-951).
///
/// 대화만 끝내는 쪽은 그림을 계속 그릴 수 있어 되돌리기 쉽고, 활동까지 끝내는 쪽은
/// 회고 저장·다음 단계로 이어져 되돌릴 수 없다. 그래서 둘을 절대 뭉뚱그리지 않는다.
const confirmedStopConversation = 'CONVERSATION';
const confirmedStopActivity = 'ACTIVITY';

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
    this.confirmedStopTarget,
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
    confirmedStopTarget: json['confirmedStopTarget'] as String?,
  );

  final int messageId;
  final int conversationId;
  final int sequence;
  final String text;
  final List<AiQuestionOption> options;
  final bool ttsAvailable;
  final DateTime createdAt;

  /// 값이 있으면 이 질문은 질문이 아니라 맺음말이며 앱이 대화를 끝내야 한다.
  ///
  /// 구버전 서버는 이 필드를 보내지 않으므로 `null`이고, 그때는 951 이전과 같게 동작한다.
  final String? confirmedStopTarget;
}
