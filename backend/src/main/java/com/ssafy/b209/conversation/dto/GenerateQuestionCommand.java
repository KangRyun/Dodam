package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.List;

/**
 * 대화 서비스가 목표 계약 요청을 만들기 위한 입력값이다.
 *
 * <p>{@code drawingActivityOpen}은 질문 내용이 아니라 <b>지금 그림 활동이 대화를 더 받을 수 있는 단계인가</b>를 실어 나른다. 공개 흐름이 활동
 * 유형을 확정하며 그림 세션을 이미 조회하므로, 아래 계층이 같은 조회를 반복하지 않도록 그때 판정한 값을 값으로 내려보낸다({@link
 * com.ssafy.b209.drawing.domain.DrawingSession#canReopenConversation()}). 끝난 대화를 다시 여는 판정에만 쓰며, 진행
 * 중 대화의 일반 질문에는 관여하지 않는다.
 */
public record GenerateQuestionCommand(
    Long conversationId,
    Long drawingSessionId,
    Long basisAnalysisId,
    int childAge,
    List<ResponseMode> allowedResponseModes,
    List<DetectedObject> detectedObjects,
    List<RecentMessage> recentMessages,
    String safetyRuleVersion,
    Long previousAnswerMessageId,
    String activityType,
    String drawingSubject,
    List<String> askedObjectCodes,
    boolean drawingActivityOpen) {

  /**
   * 이전 내부 호출과 호환되는 질문 생성 명령을 생성한다.
   *
   * <p>활동 유형·HTP 주제·기질문 대상 Code는 각각 {@code null}, {@code null}, 빈 리스트로 채워 구 호출부를 그대로 보존한다. 활동 단계는
   * {@code false}로 둔다 — 활동 유형이 {@code null}이라 이 명령으로는 어차피 재개가 성립하지 않으며, 모르는 값은 닫아 두는 쪽이 맞다.
   *
   * @param conversationId 대화 세션 식별자
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param basisAnalysisId 분석 기준 식별자
   * @param childAge AI에 제공할 만 나이
   * @param allowedResponseModes 내부 허용 응답 방식
   * @param detectedObjects AI에 제공할 대상 객체 목록
   * @param recentMessages AI에 제공할 최근 메시지 목록
   * @param safetyRuleVersion 적용할 안전 규칙 버전
   */
  public GenerateQuestionCommand(
      Long conversationId,
      Long drawingSessionId,
      Long basisAnalysisId,
      int childAge,
      List<ResponseMode> allowedResponseModes,
      List<DetectedObject> detectedObjects,
      List<RecentMessage> recentMessages,
      String safetyRuleVersion) {
    this(
        conversationId,
        drawingSessionId,
        basisAnalysisId,
        childAge,
        allowedResponseModes,
        detectedObjects,
        recentMessages,
        safetyRuleVersion,
        null,
        null,
        null,
        List.of(),
        false);
  }
}
