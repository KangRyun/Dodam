package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationSession;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 대화 세션 읽기와 질문 저장 직전의 비관 잠금을 제공한다. */
public interface ConversationSessionRepository extends JpaRepository<ConversationSession, Long> {

  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select session from ConversationSession session where session.id = :id")
  Optional<ConversationSession> findByIdForUpdate(@Param("id") Long id);

  /**
   * 그림 활동 세션에 연결된 기존 대화 세션을 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 기존 대화 세션 또는 빈 값
   */
  Optional<ConversationSession> findByDrawingSessionId(Long drawingSessionId);
}
