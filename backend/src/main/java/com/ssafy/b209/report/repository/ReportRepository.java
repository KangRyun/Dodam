package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.Report;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림 활동 리포트의 생성 접수 저장과 분석별 조회를 담당한다. */
public interface ReportRepository extends JpaRepository<Report, Long> {

  /**
   * 최종 분석에 연결된 리포트를 조회한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 리포트를 요청하지 않았거나 생성되지 않았으면 빈 값
   */
  Optional<Report> findByAnalysisId(Long analysisId);
}
