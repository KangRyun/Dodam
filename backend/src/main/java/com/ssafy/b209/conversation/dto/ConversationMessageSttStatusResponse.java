package com.ssafy.b209.conversation.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * 음성 답변 메시지의 STT 처리 상태와 변환 결과를 폴링 조회할 때 반환하는 단건 응답이다.
 *
 * <p>내부 저장소 key·절대 경로·영구 공개 URL·내부 토큰은 포함하지 않는다. {@code sttText}와 {@code sttConfidence}는 처리 상태가
 * {@code SUCCESS}일 때만 채워지며, 그 외 상태에서는 {@code null}이다.
 *
 * @param messageId 메시지 식별자
 * @param parentMessageId 답변이 연결된 질문 메시지 식별자 또는 {@code null}
 * @param sequence 세션 내 메시지 순번
 * @param senderType 발신자 유형
 * @param messageType 메시지 유형
 * @param rawText 원문 Text 또는 {@code null}
 * @param sttText 음성 인식 Text이며 {@code SUCCESS}가 아니면 {@code null}
 * @param speechStatus 음성 처리 상태
 * @param sttConfidence STT 신뢰도이며 {@code SUCCESS}가 아니면 {@code null}
 * @param needsGuardianConfirmation 보호자 확인 필요 여부
 * @param createdAt 서버가 기록한 생성 시각
 */
public record ConversationMessageSttStatusResponse(
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
    LocalDateTime createdAt) {}
