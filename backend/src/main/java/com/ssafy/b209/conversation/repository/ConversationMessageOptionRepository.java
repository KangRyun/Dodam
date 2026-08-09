package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessageOption;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 질문 메시지에 실제 노출한 선택지 Snapshot을 조회·저장한다. */
public interface ConversationMessageOptionRepository
    extends JpaRepository<ConversationMessageOption, Long> {

  /**
   * 질문 메시지에 저장된 모든 선택지 Snapshot을 조회한다.
   *
   * @param conversationMessageId 질문 메시지 식별자
   * @return 해당 질문의 선택지 Snapshot 목록
   */
  List<ConversationMessageOption> findByConversationMessageId(Long conversationMessageId);
}
