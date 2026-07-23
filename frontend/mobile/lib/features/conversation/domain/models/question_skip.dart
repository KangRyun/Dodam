// 질문 건너뛰기 요청
final class QuestionSkipRequest {
  const QuestionSkipRequest({required this.questionMessageId});

  final int questionMessageId;

  Map<String, dynamic> toJson() => {'questionMessageId': questionMessageId};
}

// 저장된 건너뛰기 결과
final class QuestionSkipResult {
  const QuestionSkipResult({required this.skipped});

  final bool skipped;
}
