package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessage;
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
}
