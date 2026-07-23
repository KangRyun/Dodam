package com.ssafy.b209.conversation.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/**
 * 대화 내역 조회에서 반환하는 단일 메시지다.
 *
 * <p>{@code messageType}은 공개 API 값(예: {@code ANSWER_OPTION})으로 노출하며 DB 저장 값을 직접 노출하지 않는다. 메시지 유형에
 * 따라 채워지는 필드가 다르며, 해당 없는 필드는 {@code null}이거나 빈 목록이다.
 *
 * @param messageId 메시지 식별자
 * @param parentMessageId 답변이 연결된 질문 메시지 식별자 또는 {@code null}
 * @param sequence 세션 내 메시지 순번
 * @param senderType 발신자 유형
 * @param messageType 공개 API 메시지 유형
 * @param rawText 원문 Text 또는 {@code null}
 * @param sttText 음성 인식 Text 또는 {@code null}
 * @param speechStatus 음성 처리 상태 또는 {@code null}
 * @param sttConfidence STT 신뢰도 또는 {@code null}
 * @param needsGuardianConfirmation 보호자 확인 필요 여부
 * @param isSkipped 건너뜀 여부
 * @param options 질문 메시지에 노출한 선택지 Snapshot 목록
 * @param selectedResponse 선택형 답변의 저장된 선택 응답 또는 {@code null}
 * @param targetObject 질문 메시지의 대상 객체 Snapshot 또는 {@code null}
 * @param createdAt 서버가 기록한 생성 시각
 */
public record ConversationMessageResponse(
    Long messageId,
    Long parentMessageId,
    int sequence,
    String senderType,
    String messageType,
    String rawText,
    String sttText,
    String speechStatus,
    BigDecimal sttConfidence,
    boolean needsGuardianConfirmation,
    boolean isSkipped,
    List<NextQuestionOptionResponse> options,
    ConversationMessageSelectedResponse selectedResponse,
    NextQuestionTargetResponse targetObject,
    LocalDateTime createdAt) {}
