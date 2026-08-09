enum ConversationCompletionReason {
  questionLimitReached('QUESTION_LIMIT_REACHED'),
  childRequest('CHILD_REQUEST'),
  guardianRequest('GUARDIAN_REQUEST'),
  noMoreQuestion('NO_MORE_QUESTION');

  const ConversationCompletionReason(this.wireName);

  final String wireName;
  String get apiValue => wireName;
}

abstract final class ConversationEndReason {
  static const childRequest = ConversationCompletionReason.childRequest;
}

// 대화 종료 요청
final class ConversationEndRequest {
  const ConversationEndRequest({
    required this.reason,
    required this.lastQuestionMessageId,
  });

  final ConversationCompletionReason reason;
  final int? lastQuestionMessageId;

  Map<String, dynamic> toJson() => {
    'reason': reason.wireName,
    'lastQuestionMessageId': ?lastQuestionMessageId,
  };
}

// 종료된 대화 상태
final class ConversationEndResult {
  const ConversationEndResult({
    required this.conversationId,
    required this.conversationStatus,
    required this.completed,
    required this.completionReason,
    required this.completedAt,
    required this.nextStage,
  });

  factory ConversationEndResult.fromJson(Map<String, dynamic> json) =>
      ConversationEndResult(
        conversationId: json['conversationId'] as int,
        conversationStatus: json['conversationStatus'] as String,
        completed: json['completed'] as bool,
        completionReason: json['completionReason'] as String,
        completedAt: json['completedAt'] as String,
        nextStage: json['nextStage'] as String,
      );

  final int conversationId;
  final String conversationStatus;
  final bool completed;
  final String completionReason, completedAt, nextStage;
}
