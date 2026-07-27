package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportActivityNoteView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 객관적 활동 주의사항을 읽는 저장소다. */
public interface ReportActivityNoteViewRepository
    extends JpaRepository<ReportActivityNoteView, Long> {

  /**
   * 리포트의 활동 주의사항을 노출 순서 오름차순으로 조회한다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 오름차순으로 정렬된 주의사항 목록
   */
  List<ReportActivityNoteView> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
