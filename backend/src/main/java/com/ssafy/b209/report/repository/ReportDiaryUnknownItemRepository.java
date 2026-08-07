package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryUnknownItem;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기에서 확인하지 못한 것을 담당한다. */
public interface ReportDiaryUnknownItemRepository
    extends JpaRepository<ReportDiaryUnknownItem, Long> {

  /**
   * 리포트에서 확인하지 못한 것을 노출 순서대로 읽는다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiaryUnknownItem> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
