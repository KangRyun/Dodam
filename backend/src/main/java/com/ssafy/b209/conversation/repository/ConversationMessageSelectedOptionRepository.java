package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 아동 선택 응답 행을 저장·조회하는 저장소다. */
public interface ConversationMessageSelectedOptionRepository
    extends JpaRepository<ConversationMessageSelectedOption, Long> {

  /**
   * 여러 답변 메시지의 선택 응답을 답변별 선택 순서대로 배치 조회한다.
   *
   * @param answerMessageIds 선택형 답변 메시지 식별자 집합
   * @return 답변별 선택 순서로 정렬된 선택 응답 목록
   */
  List<ConversationMessageSelectedOption>
      findByAnswerMessageIdInOrderByAnswerMessageIdAscSelectionOrderAsc(
          Collection<Long> answerMessageIds);
}
