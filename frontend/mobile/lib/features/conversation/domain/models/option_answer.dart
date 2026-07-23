// 선택지 답변 제출 요청
final class OptionAnswerRequest {
  const OptionAnswerRequest({
    required this.questionMessageId,
    required this.selectedOptionIds,
  });

  final int questionMessageId;
  final List<String> selectedOptionIds;

  Map<String, dynamic> toJson() => {
    'questionMessageId': questionMessageId,
    'selectedOptionIds': selectedOptionIds,
  };
}

// 저장된 선택지 답변 식별자
final class OptionAnswerResult {
  const OptionAnswerResult({required this.answerMessageId});

  final int answerMessageId;
}
