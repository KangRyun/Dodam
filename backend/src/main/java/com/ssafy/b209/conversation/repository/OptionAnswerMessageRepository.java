package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.OptionAnswerMessage;
import java.util.List;
import java.util.Optional;
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
   * <p>STT가 {@code FAILED}로 끝난 음성 답변은 답변으로 세지 않는다. 무음·저신뢰로 인식이 거절되면 아이 말은 기록에 남지 않고, 앱은 같은 질문에 선택지를
   * 띄워 다시 답하게 한다(정본 §25 "폴백 선택지 제공"). 그때 이 행을 답변으로 세면 아이가 칩을 눌러도 {@code ANSWER_ALREADY_SUBMITTED}로
   * 막혀 대화가 끊긴다.
   *
   * <p>{@code speech_status}가 {@code NULL}인 음성 답변은 상태를 알 수 없으므로 답변으로 센다 — 판정 불가를 '답변 없음'으로 넘기면 중복
   * 답변이 열린다.
   *
   * @param conversationSessionId URL 대화 세션 ID
   * @param questionMessageId 부모 질문 메시지 ID
   * @return 인식이 거절되지 않은 음성·선택·텍스트 답변이 하나라도 있으면 {@code true}
   */
  @Query(
      "select count(message) > 0 from OptionAnswerMessage message "
          + "where message.conversationSessionId = :conversationSessionId "
          + "and message.parentMessageId = :questionMessageId "
          + "and message.messageType in ('VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER') "
          + "and message.supersededAt is null "
          + "and (message.messageType <> 'VOICE_ANSWER' "
          + "or message.speechStatus is null "
          + "or message.speechStatus <> 'FAILED')")
  boolean existsAnswerForQuestion(
      @Param("conversationSessionId") Long conversationSessionId,
      @Param("questionMessageId") Long questionMessageId);

  /**
   * 이 질문을 막고 있는, 아직 글로 옮겨지지 않은 음성 답을 찾는다.
   *
   * <p>아이가 보기를 고르는 순간 이 답이 자리를 내준다. <strong>{@code SUCCESS} 는 여기 오지 않는다</strong> — 아이가 실제로 말한 답이라
   * 보기로 덮으면 안 된다. {@code FAILED} 도 오지 않는다 — 이미 중복 판정에서 빠져 막고 있지 않다.
   *
   * @param conversationSessionId 대화 세션 ID
   * @param questionMessageId 부모 질문 메시지 ID
   * @return 자리를 내줄 수 있는 음성 답이며 없으면 빈 {@link Optional}
   */
  @Query(
      "select message from OptionAnswerMessage message "
          + "where message.conversationSessionId = :conversationSessionId "
          + "and message.parentMessageId = :questionMessageId "
          + "and message.messageType = 'VOICE_ANSWER' "
          + "and message.supersededAt is null "
          + "and message.speechStatus in ('PENDING', 'PROCESSING') "
          + "order by message.messageSequence asc")
  List<OptionAnswerMessage> findSupersedableVoiceAnswers(
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
