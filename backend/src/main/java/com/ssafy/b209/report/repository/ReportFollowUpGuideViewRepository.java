package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportFollowUpGuideView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 보호자 후속 안내를 읽는 저장소다. */
public interface ReportFollowUpGuideViewRepository
    extends JpaRepository<ReportFollowUpGuideView, Long> {

  /**
   * 리포트의 후속 안내를 노출 순서 오름차순으로 조회한다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 오름차순으로 정렬된 후속 안내 목록
   */
  List<ReportFollowUpGuideView> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
