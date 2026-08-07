package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiarySessionObservation;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V2 이번 활동 관찰을 담당한다. */
public interface ReportDiarySessionObservationRepository
    extends JpaRepository<ReportDiarySessionObservation, Long> {

  /**
   * 리포트의 이번 활동 관찰을 노출 순서대로 읽는다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiarySessionObservation> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
