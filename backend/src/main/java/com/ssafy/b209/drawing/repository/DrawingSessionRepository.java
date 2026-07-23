package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingSession;
import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 활동 세션의 멱등 조회와 진행 세션 동시성 제어를 제공하는 저장소다. */
public interface DrawingSessionRepository extends JpaRepository<DrawingSession, Long> {

  /**
   * 상세 응답 조립에 필요한 아동과 그림 유형을 포함해 삭제되지 않은 세션을 조회한다.
   *
   * @param id 그림 활동 세션 식별자
   * @return 접근 가능한 세션, 존재하지 않거나 삭제됐으면 빈 값
   */
  @Query(
      "select s from DrawingSession s "
          + "join fetch s.child "
          + "join fetch s.drawingType "
          + "where s.id = :id and s.deletedAt is null")
  Optional<DrawingSession> findDetailById(@Param("id") Long id);

  /**
   * 삭제되지 않은 그림 활동 세션을 잠금 없이 조회한다.
   *
   * @param id 그림 활동 세션 식별자
   * @return 삭제되지 않은 세션, 없거나 Soft Delete된 경우 빈 값
   */
  @Query("select s from DrawingSession s where s.id = :id and s.deletedAt is null")
  Optional<DrawingSession> findNotDeletedById(@Param("id") Long id);

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

  /**
   * 아동의 삭제되지 않은 진행 중 그림 활동 세션을 모두 조회한다.
   *
   * <p>정상 데이터에서는 한 건만 존재하지만, 조회 계층이 중복 데이터를 감지할 수 있도록 목록을 반환한다. 세션 생성 시 사용하는 잠금 조회와 달리 읽기 전용이며, 응답
   * 조립에 필요한 아동과 그림 활동 유형을 함께 조회한다.
   *
   * @param childId 진행 중인 그림 활동을 확인할 아동 식별자
   * @return 식별자 오름차순으로 정렬된 진행 중 세션 목록
   */
  @Query(
      "select s from DrawingSession s "
          + "join fetch s.child "
          + "join fetch s.drawingType "
          + "where s.child.id = :childId "
          + "and s.sessionStatus = "
          + "com.ssafy.b209.drawing.domain.DrawingSessionStatus.IN_PROGRESS "
          + "and s.deletedAt is null "
          + "order by s.id asc")
  List<DrawingSession> findActiveSessionsByChildId(@Param("childId") Long childId);
}
