// 대화 종료 요청
final class ConversationEndRequest {
  const ConversationEndRequest({required this.lastQuestionMessageId});

  final int? lastQuestionMessageId;

  Map<String, dynamic> toJson() => {
    'lastQuestionMessageId': ?lastQuestionMessageId,
  };
}

// 종료된 대화 상태
final class ConversationEndResult {
  const ConversationEndResult({required this.completed});

  final bool completed;
}
