package com.ssafy.b209.drawing.repository;

import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.report.domain.ReportStatus;
import jakarta.persistence.LockModeType;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
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

  /**
   * 보호자 활동 기록 목록을 위해 아동의 삭제되지 않은 그림 활동을 필터·정렬·페이지로 조회한다.
   *
   * <p>삭제 상태이거나 Soft Delete된 세션은 제외하며, {@code null} 필터는 해당 조건을 적용하지 않는다. 리포트 상태 필터는 세션의 가장 최근 리포트
   * 상태를 기준으로 판단한다. 목록 응답 조립에 필요한 그림 활동 유형을 함께 조회해 유형별 추가 조회를 피한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param fromInclusive 시작 시각 하한(이상), 미지정이면 {@code null}
   * @param toExclusive 시작 시각 상한(미만), 미지정이면 {@code null}
   * @param drawingTypeCode 그림 활동 유형 코드 필터, 미지정이면 {@code null}
   * @param sessionStatus 세션 상태 필터, 미지정이면 {@code null}
   * @param reportStatus 최신 리포트 상태 필터, 미지정이면 {@code null}
   * @param pageable 페이지와 정렬(시작·완료 시각) 조건
   * @return 조건에 맞는 세션 페이지, 없으면 빈 페이지
   */
  @Query(
      value =
          "select s from DrawingSession s "
              + "join fetch s.drawingType t "
              + "where s.child.id = :childId "
              + "and s.deletedAt is null "
              + "and s.sessionStatus <> "
              + "com.ssafy.b209.drawing.domain.DrawingSessionStatus.DELETED "
              + "and s.sessionStatus <> "
              + "com.ssafy.b209.drawing.domain.DrawingSessionStatus.ABANDONED "
              + "and (:fromInclusive is null or s.startedAt >= :fromInclusive) "
              + "and (:toExclusive is null or s.startedAt < :toExclusive) "
              + "and (:drawingTypeCode is null or t.code = :drawingTypeCode) "
              + "and (:sessionStatus is null or s.sessionStatus = :sessionStatus) "
              // HTP는 현재까지 생성된 마지막 단계만 목록 대표 항목으로 페이지 처리한다.
              + "and (not exists ("
              + "  select 1 from HtpAssessmentStep htpStep "
              + "  where htpStep.drawingSession = s"
              + ") or exists ("
              + "  select 1 from HtpAssessmentStep htpStep "
              + "  where htpStep.drawingSession = s "
              + "  and htpStep.stepOrder = ("
              + "    select max(otherStep.stepOrder) from HtpAssessmentStep otherStep "
              + "    where otherStep.assessment = htpStep.assessment"
              + "  )"
              + ")) "
              + "and (:reportStatus is null or exists ("
              + "  select 1 from Report r "
              + "  where r.drawingSession = s "
              + "  and r.status = :reportStatus "
              + "  and not exists ("
              + "    select 1 from Report r2 "
              + "    where r2.drawingSession = s "
              + "    and (r2.createdAt > r.createdAt "
              + "      or (r2.createdAt = r.createdAt and r2.id > r.id)))))",
      countQuery =
          "select count(s) from DrawingSession s "
              + "where s.child.id = :childId "
              + "and s.deletedAt is null "
              + "and s.sessionStatus <> "
              + "com.ssafy.b209.drawing.domain.DrawingSessionStatus.DELETED "
              + "and s.sessionStatus <> "
              + "com.ssafy.b209.drawing.domain.DrawingSessionStatus.ABANDONED "
              + "and (:fromInclusive is null or s.startedAt >= :fromInclusive) "
              + "and (:toExclusive is null or s.startedAt < :toExclusive) "
              + "and (:drawingTypeCode is null or s.drawingType.code = :drawingTypeCode) "
              + "and (:sessionStatus is null or s.sessionStatus = :sessionStatus) "
              + "and (not exists ("
              + "  select 1 from HtpAssessmentStep htpStep "
              + "  where htpStep.drawingSession = s"
              + ") or exists ("
              + "  select 1 from HtpAssessmentStep htpStep "
              + "  where htpStep.drawingSession = s "
              + "  and htpStep.stepOrder = ("
              + "    select max(otherStep.stepOrder) from HtpAssessmentStep otherStep "
              + "    where otherStep.assessment = htpStep.assessment"
              + "  )"
              + ")) "
              + "and (:reportStatus is null or exists ("
              + "  select 1 from Report r "
              + "  where r.drawingSession = s "
              + "  and r.status = :reportStatus "
              + "  and not exists ("
              + "    select 1 from Report r2 "
              + "    where r2.drawingSession = s "
              + "    and (r2.createdAt > r.createdAt "
              + "      or (r2.createdAt = r.createdAt and r2.id > r.id)))))")
  Page<DrawingSession> findHistoryPage(
      @Param("childId") Long childId,
      @Param("fromInclusive") LocalDateTime fromInclusive,
      @Param("toExclusive") LocalDateTime toExclusive,
      @Param("drawingTypeCode") String drawingTypeCode,
      @Param("sessionStatus") DrawingSessionStatus sessionStatus,
      @Param("reportStatus") ReportStatus reportStatus,
      Pageable pageable);

  /**
   * 월간 감정 달력 집계를 위해 시작 시각 범위에 속한 활동과 아동 선택 감정을 한 Query로 조회한다.
   *
   * <p>세션과 선택 감정을 한 번만 LEFT JOIN하므로 활동 수만큼 추가 Query가 발생하지 않는다. 선택 감정이 여러 건인 세션은 감정 수만큼 행이 반환되므로 활동
   * 수를 세는 계층이 세션 식별자로 중복을 제거해야 한다. 선택 감정이 없는 세션도 감정 값이 {@code null}인 한 행으로 반환된다.
   *
   * <p>Soft Delete된 활동과 삭제·중단 상태 활동은 활동 기록 목록과 같은 기준으로 제외한다. 완료 리포트 수는 {@code count(*)} 스칼라
   * Subquery로 세어 조인으로 행이 늘어나지 않게 한다.
   *
   * <p>시작 시각은 저장된 UTC 기준 벽시계 값과 비교하므로 달력 기준 시간대의 월 경계를 UTC로 변환한 값을 전달해야 한다.
   *
   * @param childId 조회 대상 아동 식별자
   * @param fromInclusive UTC 기준 시작 시각 하한(이상)
   * @param toExclusive UTC 기준 시작 시각 상한(미만)
   * @return 시작 시각과 선택 순서로 정렬된 활동·감정 행 목록, 없으면 빈 목록
   */
  @Query(
      value =
          """
          select ds.id as drawingSessionId,
                 ds.started_at as startedAt,
                 e.emotion_code as emotionCode,
                 (select count(*)
                    from reports r
                   where r.drawing_session_id = ds.id
                     and r.report_status = 'COMPLETED') as completedReportCount
            from drawing_sessions ds
            left join drawing_session_emotions e on e.drawing_session_id = ds.id
           where ds.child_id = :childId
             and ds.deleted_at is null
             and ds.session_status not in ('DELETED', 'ABANDONED')
             and ds.started_at >= :fromInclusive
             and ds.started_at < :toExclusive
           order by ds.started_at, ds.id, e.selection_order, e.id
          """,
      nativeQuery = true)
  List<EmotionCalendarRowProjection> findEmotionCalendarRows(
      @Param("childId") Long childId,
      @Param("fromInclusive") LocalDateTime fromInclusive,
      @Param("toExclusive") LocalDateTime toExclusive);
}
