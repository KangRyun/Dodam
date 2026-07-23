package com.ssafy.b209.conversation.dto;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 선택형 답변 저장 결과다. 음성 답변 응답(12.5)과 대칭이 되도록 구성하며 아동·보호자 개인정보는 포함하지 않는다.
 *
 * @param messageId 생성된 답변 메시지 ID
 * @param conversationId 답변이 속한 대화 세션 ID
 * @param parentMessageId 연결한 질문 메시지 ID
 * @param sequence 세션 내 메시지 순번
 * @param senderType 항상 {@code CHILD}
 * @param messageType 항상 공개 API 값 {@code ANSWER_OPTION}
 * @param selectedOptions 저장된 선택 항목을 요청 순서대로 재생한 목록
 * @param directText 저장한 문장 직접 입력 값 또는 {@code null}
 * @param createdAt 서버가 기록한 생성 시각
 */
public record OptionAnswerResponse(
    Long messageId,
    Long conversationId,
    Long parentMessageId,
    int sequence,
    String senderType,
    String messageType,
    List<SelectedOptionCommand> selectedOptions,
    String directText,
    LocalDateTime createdAt) {}
