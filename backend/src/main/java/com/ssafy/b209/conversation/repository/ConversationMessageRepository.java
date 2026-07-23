package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.dto.KeyConversationSource;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 세션별 다음 메시지 순번을 계산한다. */
public interface ConversationMessageRepository extends JpaRepository<ConversationMessage, Long> {

  /**
   * 세션 안에서 새 메시지에 부여할 마지막 순번을 조회한다.
   *
   * <p>호출자는 대화 세션 비관 잠금 안에서 이 값을 사용해 v1.2의 세션별 순번 UNIQUE 제약과 함께 순번을 결정한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 메시지가 없으면 0, 있으면 최대 순번
   */
  @Query(
      "select coalesce(max(message.messageSequence), 0) "
          + "from ConversationMessage message "
          + "where message.conversationSessionId = :conversationSessionId")
  int findMaxMessageSequenceByConversationSessionId(
      @Param("conversationSessionId") Long conversationSessionId);

  /**
   * 지정 대화에 속한 메시지를 조회한다.
   *
   * @param id 메시지 식별자
   * @param conversationSessionId 대화 세션 식별자
   * @return 같은 세션의 메시지 또는 빈 값
   */
  Optional<ConversationMessage> findByIdAndConversationSessionId(
      Long id, Long conversationSessionId);

  /**
   * 세션에서 실제 제시한 질문 메시지 수를 집계한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return QUESTION 유형 메시지 수
   */
  @Query(
      value =
          "SELECT COUNT(*) FROM conversation_messages "
              + "WHERE conversation_session_id = :sessionId AND message_type = 'QUESTION'",
      nativeQuery = true)
  long countQuestions(@Param("sessionId") Long conversationSessionId);

  /**
   * 세션에서 건너뛰지 않고 실제 응답한 답변 메시지 수를 집계한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 응답 완료 답변 수
   */
  @Query(
      value =
          "SELECT COUNT(*) FROM conversation_messages "
              + "WHERE conversation_session_id = :sessionId "
              + "AND message_type IN ('VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER') "
              + "AND is_skipped = FALSE",
      nativeQuery = true)
  long countAnswered(@Param("sessionId") Long conversationSessionId);

  /**
   * 세션에서 건너뛴 질문 메시지 수를 집계한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 건너뛴 메시지 수
   */
  @Query(
      value =
          "SELECT COUNT(*) FROM conversation_messages "
              + "WHERE conversation_session_id = :sessionId AND is_skipped = TRUE",
      nativeQuery = true)
  long countSkipped(@Param("sessionId") Long conversationSessionId);

  /**
   * 세션에서 음성 인식에 실패한 답변 메시지 수를 집계한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 음성 인식 실패 메시지 수
   */
  @Query(
      value =
          "SELECT COUNT(*) FROM conversation_messages "
              + "WHERE conversation_session_id = :sessionId AND speech_status = 'FAILED'",
      nativeQuery = true)
  long countUnrecognizedSpeech(@Param("sessionId") Long conversationSessionId);

  /**
   * 세션에서 실제 응답이 이어진 질문·답변 쌍을 순번 순으로 조회한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 질문 순번 순서의 대표 대화 원본 목록
   */
  @Query(
      value =
          "SELECT q.id AS questionMessageId, q.raw_text AS questionText, "
              + "a.id AS answerMessageId, COALESCE(a.stt_text, a.raw_text) AS answerText, "
              + "a.message_type AS answerType "
              + "FROM conversation_messages q "
              + "JOIN conversation_messages a "
              + "ON a.parent_message_id = q.id "
              + "AND a.conversation_session_id = q.conversation_session_id "
              + "WHERE q.conversation_session_id = :sessionId "
              + "AND q.message_type = 'QUESTION' "
              + "AND a.message_type IN ('VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER') "
              + "AND a.is_skipped = FALSE "
              + "ORDER BY q.message_sequence ASC, a.message_sequence ASC",
      nativeQuery = true)
  List<KeyConversationSource> findKeyConversationSources(
      @Param("sessionId") Long conversationSessionId);
}
