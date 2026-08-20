package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryVisualObservation;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V3의 이미지 기반 관찰 사실을 저장하고 순서대로 조회한다. */
public interface ReportDiaryVisualObservationRepository
    extends JpaRepository<ReportDiaryVisualObservation, Long> {

  /**
   * @param reportId 리포트 식별자
   * @return 표시 순서대로 정렬된 그림 관찰 사실
   */
  List<ReportDiaryVisualObservation> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
