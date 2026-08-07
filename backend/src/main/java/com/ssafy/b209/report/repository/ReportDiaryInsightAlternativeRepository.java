package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryInsightAlternative;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 인사이트의 다른 설명을 담당한다. */
public interface ReportDiaryInsightAlternativeRepository
    extends JpaRepository<ReportDiaryInsightAlternative, Long> {

  /**
   * 리포트의 다른 설명을 소유 카드·순서대로 읽는다. 호출부가 카드로 묶어 쓴다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiaryInsightAlternative> findByReportIdOrderByObservationOrderAscDisplayOrderAsc(
      Long reportId);
}
