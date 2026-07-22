package com.ssafy.b209.conversation.repository;

import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 대화 시작 시 그림 활동 세션을 직렬화해 조회하는 저장소다. */
public interface ConversationStartDrawingSessionRepository
    extends JpaRepository<ConversationStartDrawingSession, Long> {

  /**
   * Soft Delete되지 않은 그림 활동 세션을 쓰기 잠금으로 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 잠금이 획득된 세션 또는 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select s from ConversationStartDrawingSession s where s.id = :drawingSessionId and s.deletedAt is null")
  Optional<ConversationStartDrawingSession> findActiveByIdForUpdate(
      @Param("drawingSessionId") Long drawingSessionId);
}
