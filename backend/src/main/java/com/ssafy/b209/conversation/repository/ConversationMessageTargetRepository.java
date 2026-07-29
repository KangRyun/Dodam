package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessageTarget;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ConversationMessageTargetRepository
    extends JpaRepository<ConversationMessageTarget, Long> {

  /**
   * 대화 전체에서 이미 질문한 대상 객체 Code를 중복 없이 조회한다.
   *
   * <p>{@code ConversationMessageTarget}과 {@code ConversationMessage} 사이에 매핑된 연관관계가 없어 메시지 식별자로
   * ad-hoc 조인한다. 대상 객체가 없는 질문 메시지는 {@code object_code}가 비어 있으므로 제외한다.
   *
   * @param conversationId 대화 세션 식별자
   * @return 질문된 대상 객체 Code의 중복 없는 목록, 없으면 빈 목록
   */
  @Query(
      "select distinct t.objectCode from ConversationMessageTarget t "
          + "join ConversationMessage m on m.id = t.conversationMessageId "
          + "where m.conversationSessionId = :conversationId and t.objectCode is not null")
  List<String> findAskedObjectCodes(@Param("conversationId") Long conversationId);
}
