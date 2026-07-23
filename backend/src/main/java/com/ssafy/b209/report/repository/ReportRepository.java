package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.Report;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림 활동 리포트의 생성 접수 저장과 분석별 조회를 담당한다. */
public interface ReportRepository extends JpaRepository<Report, Long> {

  /**
   * 세션에서 가장 최근 생성된 리포트를 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 생성 시각과 식별자 역순의 첫 번째 리포트, 없으면 빈 값
   */
  Optional<Report> findFirstByDrawingSessionIdOrderByCreatedAtDescIdDesc(Long drawingSessionId);

  /**
   * 최종 분석에 연결된 리포트를 조회한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 리포트를 요청하지 않았거나 생성되지 않았으면 빈 값
   */
  Optional<Report> findByAnalysisId(Long analysisId);
}
