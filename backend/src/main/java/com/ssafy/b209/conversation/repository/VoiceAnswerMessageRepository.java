package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.VoiceAnswerMessage;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 음성 답변의 부모 질문 검증과 세션 순번 계산을 제공하는 저장소다. */
public interface VoiceAnswerMessageRepository extends JpaRepository<VoiceAnswerMessage, Long> {

  /**
   * URL 대화 세션에 실제로 속한 QUESTION 메시지만 조회한다.
   *
   * @param messageId metadata가 지정한 부모 메시지 ID
   * @param conversationSessionId URL 대화 세션 ID
   * @return 세션 소속 QUESTION 메시지 또는 빈 값
   */
  @Query(
      "select message from VoiceAnswerMessage message "
          + "where message.id = :messageId "
          + "and message.conversationSessionId = :conversationSessionId "
          + "and message.messageType = 'QUESTION'")
  Optional<VoiceAnswerMessage> findQuestionByIdAndConversationSessionId(
      @Param("messageId") Long messageId,
      @Param("conversationSessionId") Long conversationSessionId);

  /**
   * 세션 잠금 안에서 다음 답변에 사용할 마지막 메시지 순번을 구한다.
   *
   * @param conversationSessionId 대화 세션 ID
   * @return 메시지가 없으면 0, 아니면 현재 최대 순번
   */
  @Query(
      "select coalesce(max(message.messageSequence), 0) from VoiceAnswerMessage message "
          + "where message.conversationSessionId = :conversationSessionId")
  int findMaxMessageSequenceByConversationSessionId(
      @Param("conversationSessionId") Long conversationSessionId);
}
