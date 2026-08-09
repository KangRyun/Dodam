package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryDevelopmentSource;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 발달 맥락의 검수 출처를 담당한다. */
public interface ReportDiaryDevelopmentSourceRepository
    extends JpaRepository<ReportDiaryDevelopmentSource, Long> {

  /**
   * 리포트의 검수 출처를 도메인·순서대로 읽는다. 호출부가 도메인으로 묶어 쓴다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiaryDevelopmentSource> findByReportIdOrderByDomainAscDisplayOrderAsc(Long reportId);
}
