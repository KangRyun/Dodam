package com.ssafy.b209.conversation.dto;

/**
 * 질문 건너뛰기 처리 결과다.
 *
 * <p>그림 활동 단계는 이 API로 바뀌지 않는다(§12.8의 {@code returnToDrawing}은 미지원). 화면은 {@code skipped}로 다음 질문
 * 요청 여부를 판단한다.
 *
 * @param conversationId 대화 세션 식별자
 * @param questionMessageId 건너뛴 질문 메시지 식별자
 * @param skipped 건너뜀 저장 여부. 재전송이나 이미 건너뛴 질문도 {@code true}다
 * @param alreadySkipped 이 요청 전에 이미 건너뛴 상태였는지
 * @param skippedQuestionCount 대화에서 건너뛴 질문 수
 * @param conversationStatus 처리 후 대화 상태
 */
public record SkipQuestionResponse(
    Long conversationId,
    Long questionMessageId,
    boolean skipped,
    boolean alreadySkipped,
    int skippedQuestionCount,
    String conversationStatus) {}
