import 'ai_question.dart';

// 선택지 답변 제출 요청
//
// 백엔드 OptionAnswerRequest 계약(2026-07-24 확인)은 선택지 id뿐 아니라
// 선택 당시의 스냅샷(type·value·labelSnapshot, 전부 필수)을 요구하므로
// id 목록이 아니라 선택지 객체 자체를 담아 전송한다.
//
// 질문 응답의 type은 화면 노출용 OPTION이지만, 답변 저장 계약은
// DB 선택지 스냅샷 유형인 STATIC을 요구한다.
final class OptionAnswerRequest {
  const OptionAnswerRequest({
    required this.questionMessageId,
    required this.selectedOptions,
  });

  final int questionMessageId;
  final List<AiQuestionOption> selectedOptions;

  Map<String, dynamic> toJson() => {
    'questionMessageId': questionMessageId,
    'selectedOptions': [
      for (final option in selectedOptions)
        {
          'optionId': option.optionId,
          'type': 'STATIC',
          'value': option.value,
          // BE 필드명은 labelSnapshot — 답변 시점의 라벨 보존용
          'labelSnapshot': option.label,
        },
    ],
  };
}

// 저장된 선택지 답변 식별자
final class OptionAnswerResult {
  const OptionAnswerResult({required this.answerMessageId});

  final int answerMessageId;
}
