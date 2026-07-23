package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportConversationSummaryView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 대화 요약의 대체 출처를 읽는 저장소다. */
public interface ReportConversationSummaryViewRepository
    extends JpaRepository<ReportConversationSummaryView, Long> {

  /**
   * 분석의 대화 요약을 요약 식별자 오름차순으로 조회한다.
   *
   * @param analysisId 최종 분석 식별자
   * @return 요약 식별자 오름차순으로 정렬된 대화 요약 목록
   */
  List<ReportConversationSummaryView> findByAnalysisIdOrderByIdAsc(Long analysisId);
}
