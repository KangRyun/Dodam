package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationHistoryTarget;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** CONV-02 조회에서 질문 대상 객체 Snapshot을 배치로 읽는 읽기 저장소다. */
public interface ConversationHistoryTargetRepository
    extends JpaRepository<ConversationHistoryTarget, Long> {

  /**
   * 여러 질문 메시지의 대상 객체 Snapshot을 배치 조회한다.
   *
   * @param conversationMessageIds 질문 메시지 식별자 집합
   * @return 조회된 대상 객체 Snapshot 목록
   */
  List<ConversationHistoryTarget> findByConversationMessageIdIn(
      Collection<Long> conversationMessageIds);
}
