// 대화 종료 요청
enum ConversationCompletionReason {
  questionLimitReached('QUESTION_LIMIT_REACHED'),
  childRequest('CHILD_REQUEST'),
  guardianRequest('GUARDIAN_REQUEST'),
  noMoreQuestion('NO_MORE_QUESTION');

  const ConversationCompletionReason(this.wireName);

  final String wireName;
}

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
  const ConversationEndResult({required this.completed});

  final bool completed;
}
