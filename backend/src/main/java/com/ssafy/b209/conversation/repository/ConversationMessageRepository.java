package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 세션별 다음 메시지 순번을 계산한다. */
public interface ConversationMessageRepository extends JpaRepository<ConversationMessage, Long> {

  @Query(
      "select coalesce(max(message.messageSequence), 0) "
          + "from ConversationMessage message "
          + "where message.conversationSessionId = :conversationSessionId")
  int findMaxMessageSequenceByConversationSessionId(
      @Param("conversationSessionId") Long conversationSessionId);
}
