package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationHistoryOption;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** CONV-02 조회에서 질문 선택지 Snapshot을 배치로 읽는 읽기 저장소다. */
public interface ConversationHistoryOptionRepository
    extends JpaRepository<ConversationHistoryOption, Long> {

  /**
   * 여러 질문 메시지의 선택지 Snapshot을 노출 순서대로 배치 조회한다.
   *
   * @param conversationMessageIds 질문 메시지 식별자 집합
   * @return 질문별 노출 순서로 정렬된 선택지 Snapshot 목록
   */
  List<ConversationHistoryOption>
      findByConversationMessageIdInOrderByConversationMessageIdAscDisplayOrderAsc(
          Collection<Long> conversationMessageIds);

  /**
   * 선택 응답이 참조하는 선택지 Snapshot 행을 식별자로 배치 조회한다.
   *
   * @param ids 선택지 Snapshot 행 식별자 집합
   * @return 조회된 선택지 Snapshot 목록
   */
  List<ConversationHistoryOption> findByIdIn(Collection<Long> ids);
}
