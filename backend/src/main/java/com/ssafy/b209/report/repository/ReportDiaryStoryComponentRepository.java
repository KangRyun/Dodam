package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryStoryComponent;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V3 이야기 구성 요소를 저장하고 순서대로 조회한다. */
public interface ReportDiaryStoryComponentRepository
    extends JpaRepository<ReportDiaryStoryComponent, Long> {

  /**
   * @param reportId 리포트 식별자
   * @return 표시 순서대로 정렬된 이야기 구성 요소
   */
  List<ReportDiaryStoryComponent> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
