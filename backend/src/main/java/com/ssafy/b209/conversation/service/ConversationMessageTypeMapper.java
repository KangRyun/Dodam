package com.ssafy.b209.conversation.service;

/**
 * DB에 저장된 대화 메시지 유형을 외부 공개 API 표현으로 변환하는 매퍼다.
 *
 * <p>변환은 조회 경계에서만 수행하며, API DTO와 DB CHECK 어느 쪽에도 새로운 값을 추가하지 않는다. 매핑이 정의되지 않은 값은 원문을 그대로 반환한다.
 */
public final class ConversationMessageTypeMapper {

  private ConversationMessageTypeMapper() {}

  /**
   * DB {@code conversation_messages.message_type} 값을 공개 API 메시지 유형으로 변환한다.
   *
   * @param messageType DB 저장 메시지 유형
   * @return 공개 계약에 정의된 메시지 유형이며, 매핑이 없으면 원문
   */
  public static String toPublicMessageType(String messageType) {
    return switch (messageType) {
      case "VOICE_ANSWER" -> "ANSWER_VOICE";
      case "OPTION_ANSWER" -> "ANSWER_OPTION";
      case "TEXT_ANSWER" -> "ANSWER_TEXT";
      case "SYSTEM_NOTICE" -> "SYSTEM";
      default -> messageType;
    };
  }
}
