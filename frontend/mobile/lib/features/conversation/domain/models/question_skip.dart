// 질문 건너뛰기 요청
final class QuestionSkipRequest {
  const QuestionSkipRequest({required this.questionMessageId});

  final int questionMessageId;

  Map<String, dynamic> toJson() => {'questionMessageId': questionMessageId};
}

// 저장된 건너뛰기 결과
final class QuestionSkipResult {
  const QuestionSkipResult({required this.skipped});

  /// 서버 응답에서 건너뜀 저장 여부를 읽는다.
  ///
  /// 서버는 이미 건너뛴 질문의 재요청에도 `skipped=true`를 반환한다. 필드가 없으면
  /// 성공 응답을 실패로 뒤집지 않기 위해 `true`로 본다.
  factory QuestionSkipResult.fromJson(Map<String, dynamic> json) =>
      QuestionSkipResult(skipped: json['skipped'] as bool? ?? true);

  final bool skipped;
}
