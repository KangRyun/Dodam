package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** CONV-02 대화 내역을 순번 오름차순으로 페이지 조회하는 읽기 저장소다. */
public interface ConversationHistoryMessageRepository
    extends JpaRepository<ConversationHistoryMessage, Long> {

  /**
   * 세션의 메시지를 순번 오름차순으로 페이지 조회한다.
   *
   * <p>{@code afterSequence}가 주어지면 해당 순번 이후 메시지만 조회하는 커서 조건을 적용한다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @param afterSequence 커서 기준 순번 또는 처음부터 조회할 {@code null}
   * @param pageable 순번 오름차순으로 정렬된 페이지 요청
   * @return 조건에 맞는 메시지 페이지
   */
  @Query(
      "select message from ConversationHistoryMessage message "
          + "where message.conversationSessionId = :conversationSessionId "
          + "and (:afterSequence is null or message.messageSequence > :afterSequence) "
          + "order by message.messageSequence asc")
  Page<ConversationHistoryMessage> findPage(
      @Param("conversationSessionId") Long conversationSessionId,
      @Param("afterSequence") Integer afterSequence,
      Pageable pageable);
}
