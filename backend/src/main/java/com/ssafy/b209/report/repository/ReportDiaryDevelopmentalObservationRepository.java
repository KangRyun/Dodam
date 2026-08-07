package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryDevelopmentalObservation;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 연령 발달 맥락 관찰을 담당한다. */
public interface ReportDiaryDevelopmentalObservationRepository
    extends JpaRepository<ReportDiaryDevelopmentalObservation, Long> {

  /**
   * 리포트의 발달 맥락 관찰을 노출 순서대로 읽는다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiaryDevelopmentalObservation> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
