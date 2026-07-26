package com.ssafy.b209.conversation.service;

/**
 * 288 음성 답변이 PENDING 상태로 저장된 뒤 289 STT 처리를 요청하는 도메인 이벤트다.
 *
 * <p>업로드 Transaction이 커밋된 뒤에만 처리하도록 {@code AFTER_COMMIT} 단계에서 소비한다. 커밋되지 않은 메시지 ID로 STT를 시작하지 않기 위한
 * 경계다.
 *
 * @param conversationMessageId STT 처리 대상 VOICE_ANSWER 메시지 식별자
 */
public record VoiceAnswerStoredEvent(Long conversationMessageId) {}
