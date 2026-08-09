package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import java.util.List;
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

  /**
   * 다음 AI 질문 요청에 실을 세션의 최근 질문·답변 메시지를 순번 내림차순으로 조회한다.
   *
   * <p>건너뛴 <strong>답변</strong>과 시스템 안내는 대화 문맥이 아니므로 제외하며, 실제 문맥 순서(순번 오름차순)로 재배열하는 책임은 호출자에게 둔다. 조회
   * 건수는 {@code pageable}의 크기로 제한한다.
   *
   * <p><strong>건너뛴 질문은 남긴다.</strong> 질문 건너뛰기({@code POST /conversations/{id}/skip})는 답변이 아니라 <em>질문
   * 행</em>에 {@code skipped = true}를 찍는다. 그래서 건너뜀 전체를 제외하면 그 질문이 AI 문맥에서 사라져, AI가 받는 재료가 질문 직전과 같아지고
   * 같은 질문을 다시 만든다 — 아이가 넘겨도 같은 질문이 반복된다. 답이 뒤따르지 않는 질문으로 남겨야 AI가 "이미 물어봤다"를 알 수 있다.
   *
   * @param conversationSessionId 대화 세션 식별자
   * @param pageable 최근 순 정렬과 건수 제한을 담은 페이지 요청
   * @return 순번 내림차순의 최근 질문·답변 메시지(건너뛴 질문 포함), 없으면 빈 목록
   */
  @Query(
      "select message from ConversationHistoryMessage message "
          + "where message.conversationSessionId = :conversationSessionId "
          + "and message.messageType in ('QUESTION', 'VOICE_ANSWER', 'OPTION_ANSWER', 'TEXT_ANSWER') "
          + "and (message.skipped = false or message.messageType = 'QUESTION') "
          + "order by message.messageSequence desc")
  List<ConversationHistoryMessage> findRecentContextMessages(
      @Param("conversationSessionId") Long conversationSessionId, Pageable pageable);
}
