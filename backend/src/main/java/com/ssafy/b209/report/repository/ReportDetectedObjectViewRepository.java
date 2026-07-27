package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDetectedObjectView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 탐지 객체명을 읽는 저장소다. */
public interface ReportDetectedObjectViewRepository
    extends JpaRepository<ReportDetectedObjectView, Long> {

  /**
   * 분석의 탐지 객체를 탐지 순서 오름차순으로 조회한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 탐지 순서 오름차순으로 정렬된 탐지 객체 목록
   */
  List<ReportDetectedObjectView> findByAnalysisIdOrderByDetectionOrderAsc(Long analysisId);
}
