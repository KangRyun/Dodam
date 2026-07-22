package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingSession;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 활동 세션의 멱등 조회와 진행 세션 동시성 제어를 제공하는 저장소다. */
public interface DrawingSessionRepository extends JpaRepository<DrawingSession, Long> {

  /**
   * 삭제되지 않은 그림 활동 세션을 현재 Transaction의 쓰기 잠금으로 조회한다.
   *
   * @param id 그림 활동 세션 식별자
   * @return 삭제되지 않은 세션, 없거나 Soft Delete된 경우 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select s from DrawingSession s where s.id = :id and s.deletedAt is null")
  Optional<DrawingSession> findNotDeletedByIdForUpdate(@Param("id") Long id);

  /**
   * 잠금을 획득하지 않고 멱등 키에 해당하는 기존 세션을 조회한다.
   *
   * @param key 요청에 사용된 멱등 키
   * @return 기존 세션, 사용된 적이 없는 키면 빈 값
   */
  Optional<DrawingSession> findByIdempotencyKey(String key);

  /**
   * 멱등 키에 해당하는 세션을 현재 읽기와 쓰기 잠금으로 조회한다.
   *
   * @param key 요청에 사용된 멱등 키
   * @return 기존 세션, 사용된 적이 없는 키면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select s from DrawingSession s where s.idempotencyKey = :key")
  Optional<DrawingSession> findByIdempotencyKeyForUpdate(@Param("key") String key);

  /**
   * 아동의 삭제되지 않은 진행 중 세션을 현재 읽기와 쓰기 잠금으로 조회한다.
   *
   * @param childId 확인할 아동 식별자
   * @return 진행 중 세션, 없으면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query(
      "select s from DrawingSession s where s.child.id = :childId "
          + "and s.sessionStatus = "
          + "com.ssafy.b209.drawing.domain.DrawingSessionStatus.IN_PROGRESS "
          + "and s.deletedAt is null")
  Optional<DrawingSession> findActiveByChildId(@Param("childId") Long childId);
}
