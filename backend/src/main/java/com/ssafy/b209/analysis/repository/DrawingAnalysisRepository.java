package com.ssafy.b209.analysis.repository;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 분석 실행의 저장, 동시성 잠금, 중복 확인과 상세 조회를 담당한다. */
public interface DrawingAnalysisRepository extends JpaRepository<DrawingAnalysis, Long> {

  /**
   * 세션에서 가장 최근 요청된 분석 실행을 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 요청 시각과 식별자 역순의 첫 번째 분석, 없으면 빈 값
   */
  Optional<DrawingAnalysis> findFirstByDrawingSessionIdOrderByRequestedAtDescIdDesc(
      Long drawingSessionId);

  /**
   * 완료 접수 요청에 사용한 멱등 키로 분석을 조회한다.
   *
   * @param requestId {@code Idempotency-Key} Header 값
   * @return 해당 키로 생성된 분석, 사용되지 않은 키면 빈 값
   */
  Optional<DrawingAnalysis> findByRequestId(String requestId);

  /**
   * 삭제되지 않은 Session에 속한 분석과 공개 응답에 필요한 Asset·Detection을 함께 조회한다.
   *
   * <p>Session ID와 Analysis ID를 동시에 조건으로 사용해 다른 Session의 분석 존재 여부를 노출하지 않는다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param drawingAnalysisId 분석 실행 식별자
   * @return Session·Asset·Detection이 초기화된 분석, 조건에 맞지 않으면 빈 값
   */
  @Query(
      "select distinct a from DrawingAnalysis a "
          + "join fetch a.drawingSession s "
          + "left join fetch a.drawingAsset asset "
          + "left join fetch asset.drawingSession "
          + "left join fetch a.detections d "
          + "where s.id = :drawingSessionId and a.id = :drawingAnalysisId "
          + "and s.deletedAt is null "
          + "order by d.displayOrder asc, d.id asc")
  Optional<DrawingAnalysis> findDetailBySessionIdAndAnalysisId(
      @Param("drawingSessionId") Long drawingSessionId,
      @Param("drawingAnalysisId") Long drawingAnalysisId);

  /**
   * 동일 그림과 작업 유형에 처리 중이거나 성공한 분석이 존재하는지 확인한다.
   *
   * @param drawingAssetId 그림 파일 식별자
   * @param taskType AI 분석 작업 유형
   * @return 재요청을 막아야 하는 분석이 있으면 {@code true}
   */
  @Query(
      "select (count(a) > 0) from DrawingAnalysis a "
          + "where a.drawingAsset.id = :drawingAssetId and a.taskType = :taskType "
          + "and a.state in (com.ssafy.b209.analysis.domain.DrawingAnalysisState.PROCESSING, "
          + "com.ssafy.b209.analysis.domain.DrawingAnalysisState.SUCCESS)")
  boolean existsActiveByAssetAndTaskType(
      @Param("drawingAssetId") Long drawingAssetId,
      @Param("taskType") DrawingAnalysisType taskType);

  /**
   * 분석 결과를 한 번만 완료 또는 실패 처리하도록 쓰기 잠금으로 조회한다.
   *
   * @param id 분석 실행 식별자
   * @return 잠근 분석 실행, 존재하지 않으면 빈 값
   */
  @Lock(LockModeType.PESSIMISTIC_WRITE)
  @Query("select a from DrawingAnalysis a where a.id = :id")
  Optional<DrawingAnalysis> findByIdForUpdate(@Param("id") Long id);
}
