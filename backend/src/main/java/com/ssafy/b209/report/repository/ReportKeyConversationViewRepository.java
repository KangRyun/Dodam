package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportKeyConversationView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 대표 대화 Snapshot을 읽는 저장소다. */
public interface ReportKeyConversationViewRepository
    extends JpaRepository<ReportKeyConversationView, Long> {

  /**
   * 리포트의 대표 대화를 노출 순서 오름차순으로 조회한다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 오름차순으로 정렬된 대표 대화 목록
   */
  List<ReportKeyConversationView> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
