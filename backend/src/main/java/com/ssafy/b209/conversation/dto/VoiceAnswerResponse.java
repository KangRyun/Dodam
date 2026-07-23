package com.ssafy.b209.conversation.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * STT 처리 전 음성 답변 생성 결과다. 내부 storage key·원본 파일명·절대 경로는 포함하지 않는다.
 *
 * @param messageId 생성된 답변 메시지 ID
 * @param parentMessageId 연결한 질문 메시지 ID
 * @param sequence 세션 내 메시지 순번
 * @param senderType 항상 {@code CHILD}
 * @param messageType 항상 {@code VOICE_ANSWER}
 * @param rawText STT 전에는 항상 {@code null}
 * @param sttText STT 전에는 항상 {@code null}
 * @param speechStatus 항상 {@code PENDING}
 * @param sttConfidence STT 전에는 항상 {@code null}
 * @param needsGuardianConfirmation STT 정책 적용 전 기본값
 * @param createdAt 서버가 기록한 생성 시각
 */
public record VoiceAnswerResponse(
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
