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
   * 대화 종료 화면이 확인한 질문과 비교할 현재 최신 질문을 조회한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @param messageType 조회할 메시지 유형
   * @return 시퀀스가 가장 큰 해당 유형 메시지 또는 메시지가 없을 때 빈 값
   */
  Optional<ConversationMessage>
      findFirstByConversationSessionIdAndMessageTypeOrderByMessageSequenceDesc(
          Long conversationSessionId, String messageType);

  /**
   * 지정한 이전 답변을 이어받은 QUESTION 메시지가 세션에 이미 있는지 확인한다.
   *
   * <p>호출자는 대화 세션 비관 잠금 안에서 이 값을 사용해, 서로 다른 요청이 같은 답변을 부모로 참조하며 질문을 두 번 생성하는 중복을 차단한다. 부모 답변 1건당 후속
   * 질문은 1건만 허용한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @param parentMessageId 이어받은 이전 답변 메시지 식별자
   * @return 같은 부모 답변을 이어받은 QUESTION 메시지가 있으면 {@code true}
   */
  @Query(
      "select count(message) > 0 from ConversationMessage message "
          + "where message.conversationSessionId = :conversationSessionId "
          + "and message.parentMessageId = :parentMessageId "
          + "and message.messageType = 'QUESTION'")
  boolean existsQuestionByParentMessageId(
      @Param("conversationSessionId") Long conversationSessionId,
      @Param("parentMessageId") Long parentMessageId);

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
   * 세션에서 아이가 실제로 답한 텍스트를 순서대로 조회한다 (S15P11B209-989).
   *
   * <p>앞 주제 대화를 다음 주제 질문 생성에 압축해 싣는 재료다 — 질문은 싣지 않고 아이 답만
   * 싣는다(프롬프트 크기). 음성 인식 결과가 있으면 그것을, 없으면 원문(선택 칩 라벨·타이핑)을 쓴다.
   * 건너뛴 질문은 답이 아니라 뺀다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 아이 답변 텍스트 목록(대화 순서), 없으면 빈 목록
   */
  @Query(
      value =
          "SELECT COALESCE(NULLIF(stt_text, ''), raw_text) FROM conversation_messages "
              + "WHERE conversation_session_id = :sessionId "
              + "AND message_type IN ('VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER') "
              + "AND is_skipped = FALSE "
              + "AND COALESCE(NULLIF(stt_text, ''), raw_text) IS NOT NULL "
              + "ORDER BY message_sequence ASC",
      nativeQuery = true)
  List<String> findChildAnswerTexts(@Param("sessionId") Long conversationSessionId);

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
   * <p><strong>고른 답의 글은 메시지에 없다.</strong> 아이가 보기만 고르면 {@code OPTION_ANSWER} 메시지의 {@code raw_text} 는
   * 비어 있고(직접 입력한 글만 거기 들어간다), 고른 문구는 {@code conversation_message_selected_options.label_snapshot} 에
   * 따로 남는다. 그 표를 읽지 않으면 답이 <b>빈 글</b>로 보여 리포트가 "이 질문은 건너뛰었어요"로 적는다 — 아이는 분명히 골랐는데
   * 기록에는 넘긴 것으로 남는다(2026-08-09 실측). 그래서 여기서 라벨을 이어 붙인다.
   *
   * <p>{@code superseded_at} 이 있는 답은 제외한다. 자동 녹음된 무음 답이 아이가 고른 답에 자리를 내주고도 목록에 남으면, 같은
   * 질문에 빈 답이 하나 더 붙어 역시 "건너뛰었어요"가 된다. 지우지 않고 남겨 두는 것은 되짚기 위해서고(V49), 읽는 쪽이 거른다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 질문 순번 순서의 대표 대화 원본 목록
   */
  @Query(
      value =
          "SELECT q.id AS questionMessageId, q.raw_text AS questionText, "
              + "a.id AS answerMessageId, "
              // 고른 문구와 직접 입력한 글을 함께 남긴다 — 둘 다 아이가 이번에 준 답이다.
              + "CASE WHEN a.message_type = 'OPTION_ANSWER' THEN NULLIF(CONCAT_WS(' ', "
              + "(SELECT GROUP_CONCAT(s.label_snapshot ORDER BY s.selection_order SEPARATOR ', ') "
              + "FROM conversation_message_selected_options s "
              + "WHERE s.answer_message_id = a.id), a.raw_text), '') "
              + "ELSE COALESCE(a.stt_text, a.raw_text) END AS answerText, "
              + "a.message_type AS answerType, "
              // 미확정 STT 를 근거·대표 발화에서 제외하려면 원 메시지 값이 필요하다(계약 §4-4).
              + "a.needs_guardian_confirmation AS answerNeedsGuardianConfirmation "
              + "FROM conversation_messages q "
              + "JOIN conversation_messages a "
              + "ON a.parent_message_id = q.id "
              + "AND a.conversation_session_id = q.conversation_session_id "
              + "WHERE q.conversation_session_id = :sessionId "
              + "AND q.message_type = 'QUESTION' "
              + "AND a.message_type IN ('VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER') "
              + "AND a.is_skipped = FALSE "
              + "AND a.superseded_at IS NULL "
              + "ORDER BY q.message_sequence ASC, a.message_sequence ASC",
      nativeQuery = true)
  List<KeyConversationSource> findKeyConversationSources(
      @Param("sessionId") Long conversationSessionId);
}
