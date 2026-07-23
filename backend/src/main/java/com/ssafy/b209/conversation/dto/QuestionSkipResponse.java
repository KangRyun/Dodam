package com.ssafy.b209.conversation.dto;

/**
 * 질문 건너뛰기 처리 결과다. 아동·보호자 개인정보는 포함하지 않으며 건너뛴 사실로 아동을 압박하는 값도 반환하지 않는다.
 *
 * @param questionMessageId 건너뛴 질문 메시지 ID
 * @param isSkipped 항상 {@code true}
 * @param questionCount 현재 질문 수이며 건너뛰기로 되돌리지 않는다
 * @param maxQuestionCount 세션의 최대 질문 수
 * @param currentStage 처리 후 그림 세션 단계({@code DRAWING} 또는 {@code CONVERSING})
 */
public record QuestionSkipResponse(
    Long questionMessageId,
    boolean isSkipped,
    int questionCount,
    int maxQuestionCount,
    String currentStage) {}
