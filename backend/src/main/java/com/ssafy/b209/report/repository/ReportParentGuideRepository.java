package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportParentGuide;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 보호자 가이드를 저장·조회하는 저장소다. */
public interface ReportParentGuideRepository extends JpaRepository<ReportParentGuide, Long> {

  /**
   * 리포트의 보호자 가이드를 유형·순서대로 조회한다.
   *
   * @param reportId 리포트 식별자
   * @return 유형 이름과 순서 오름차순 가이드 목록
   */
  List<ReportParentGuide> findByReportIdOrderByGuideTypeAscDisplayOrderAsc(Long reportId);
}
