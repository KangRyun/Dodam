enum ConversationEndReason {
  childRequest('CHILD_REQUEST');

  const ConversationEndReason(this.apiValue);

  final String apiValue;
}

// 대화 종료 요청
final class ConversationEndRequest {
  const ConversationEndRequest({
    required this.reason,
    required this.lastQuestionMessageId,
  });

  final ConversationEndReason reason;
  final int? lastQuestionMessageId;

  Map<String, dynamic> toJson() => {
    'reason': reason.apiValue,
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
