package com.ssafy.b209.analysis.repository;

import com.ssafy.b209.analysis.domain.AnalysisConversationSummary;
import org.springframework.data.jpa.repository.JpaRepository;

/** 대화 분석 요약의 저장과 분석별 존재 여부 확인을 담당한다. */
public interface AnalysisConversationSummaryRepository
    extends JpaRepository<AnalysisConversationSummary, Long> {

  /**
   * 분석에 이미 저장된 대화 요약이 있는지 확인한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 대화 요약이 존재하면 {@code true}
   */
  boolean existsByAnalysisId(Long analysisId);
}
