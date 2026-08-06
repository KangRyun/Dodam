/// 대화 시작 응답에서 화면이 실제로 쓰는 값 (S15P11B209-976).
///
/// 예전에는 conversationId 하나만 돌려주고 응답의 나머지를 버렸다. 질문 수 상한은
/// 앱 상수(`defaultConversationMaxQuestionCount = 10`)가 들고 있다가 시작 요청에
/// 실어 보냈는데, 그래서 **정책의 주인이 앱**이었다. 지금은 서버가 활동 유형(HTP 주제당 ·
/// 그림일기)에 따라 정하고 앱은 그 결과를 받아 쓴다.
final class ConversationStartResult {
  const ConversationStartResult({
    required this.conversationId,
    this.maxQuestionCount,
  });

  final int conversationId;

  /// 서버가 이 대화에 허용한 질문 수. 화면의 무응답 자동 진행 게이트가 쓴다.
  ///
  /// `null`이 될 수 있다 — 이미 진행 중인 대화를 이어받는 409 응답에는
  /// conversationId 만 실린다. 그때는 앱이 상한을 모른 채 진행하고, 상한 도달은
  /// 서버가 next-question 에서 `CONVERSATION_409_001` 로 알려준다
  /// (AiQuestionController 가 대화 종료로 처리한다). 앱이 임의의 기본값을 지어내
  /// 서버보다 먼저 대화를 끊는 것보다 낫다.
  final int? maxQuestionCount;
}
