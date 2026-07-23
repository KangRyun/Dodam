package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.OptionAnswerMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 선택형 답변 저장에 필요한 부모 질문 검증·중복 답변 확인·순번 계산을 제공하는 저장소다. */
public interface OptionAnswerMessageRepository extends JpaRepository<OptionAnswerMessage, Long> {

  /**
   * URL 대화 세션에 실제로 속한 QUESTION 메시지가 존재하는지 확인한다.
   *
   * @param messageId 요청이 지정한 부모 질문 메시지 ID
   * @param conversationSessionId URL 대화 세션 ID
   * @return 세션 소속 QUESTION 메시지가 있으면 {@code true}
   */
  @Query(
      "select count(message) > 0 from OptionAnswerMessage message "
          + "where message.id = :messageId "
          + "and message.conversationSessionId = :conversationSessionId "
          + "and message.messageType = 'QUESTION'")
  boolean existsQuestion(
      @Param("messageId") Long messageId,
      @Param("conversationSessionId") Long conversationSessionId);

  /**
   * 지정 질문에 이미 아동 답변 메시지가 저장돼 있는지 확인한다.
   *
   * @param conversationSessionId URL 대화 세션 ID
   * @param questionMessageId 부모 질문 메시지 ID
   * @return 음성·선택·텍스트 답변 중 하나라도 이미 있으면 {@code true}
   */
  @Query(
      "select count(message) > 0 from OptionAnswerMessage message "
          + "where message.conversationSessionId = :conversationSessionId "
          + "and message.parentMessageId = :questionMessageId "
          + "and message.messageType in ('VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER')")
  boolean existsAnswerForQuestion(
      @Param("conversationSessionId") Long conversationSessionId,
      @Param("questionMessageId") Long questionMessageId);

  /**
   * 세션 잠금 안에서 다음 답변에 사용할 마지막 메시지 순번을 구한다.
   *
   * @param conversationSessionId 대화 세션 ID
   * @return 메시지가 없으면 0, 아니면 현재 최대 순번
   */
  @Query(
      "select coalesce(max(message.messageSequence), 0) from OptionAnswerMessage message "
          + "where message.conversationSessionId = :conversationSessionId")
  int findMaxMessageSequenceByConversationSessionId(
      @Param("conversationSessionId") Long conversationSessionId);
}
