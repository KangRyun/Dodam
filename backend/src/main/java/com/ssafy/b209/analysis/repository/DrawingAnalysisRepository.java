package com.ssafy.b209.analysis.repository;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** 그림 분석 실행의 저장, 동시성 잠금과 활성 분석 중복 조회를 담당한다. */
public interface DrawingAnalysisRepository extends JpaRepository<DrawingAnalysis, Long> {

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
