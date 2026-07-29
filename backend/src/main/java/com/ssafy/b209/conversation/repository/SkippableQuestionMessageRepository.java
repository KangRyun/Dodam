package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.SkippableQuestionMessage;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 질문 건너뛰기(CONV-08)가 쓰는 질문 메시지 조회·집계 경계다. */
public interface SkippableQuestionMessageRepository
    extends JpaRepository<SkippableQuestionMessage, Long> {

  /**
   * 지정 대화에 속한 메시지를 건너뜀 표시와 함께 조회한다.
   *
   * <p>대화 식별자를 조건에 포함해 다른 대화의 메시지 식별자로 건너뛰는 것을 막는다.
   *
   * @param id 메시지 식별자
   * @param conversationSessionId 대화 세션 식별자
   * @return 같은 대화의 메시지 또는 빈 값
   */
  Optional<SkippableQuestionMessage> findByIdAndConversationSessionId(
      Long id, Long conversationSessionId);

  /**
   * 대화에서 건너뛴 질문 수를 센다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @return 건너뜀으로 표시된 메시지 수
   */
  int countByConversationSessionIdAndSkippedTrue(Long conversationSessionId);
}
