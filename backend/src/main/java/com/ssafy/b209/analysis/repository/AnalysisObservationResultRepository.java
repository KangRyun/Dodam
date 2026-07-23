package com.ssafy.b209.analysis.repository;

import com.ssafy.b209.analysis.domain.AnalysisObservationResult;
import org.springframework.data.jpa.repository.JpaRepository;

/** 분석 관찰 결과의 저장과 분석별 존재 여부 확인을 담당한다. */
public interface AnalysisObservationResultRepository
    extends JpaRepository<AnalysisObservationResult, Long> {

  /**
   * 분석에 이미 저장된 관찰 결과가 있는지 확인한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 관찰 결과가 존재하면 {@code true}
   */
  boolean existsByAnalysisId(Long analysisId);
}
