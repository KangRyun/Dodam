package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.List;

/** 대화 서비스가 목표 계약 요청을 만들기 위한 입력값이다. */
public record GenerateQuestionCommand(
    Long conversationId,
    Long drawingSessionId,
    Long basisAnalysisId,
    int childAge,
    List<ResponseMode> allowedResponseModes,
    List<DetectedObject> detectedObjects,
    List<RecentMessage> recentMessages,
    String safetyRuleVersion,
    Long previousAnswerMessageId) {

  /**
   * 이전 내부 호출과 호환되는 질문 생성 명령을 생성한다.
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
        null);
  }
}
