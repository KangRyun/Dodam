package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDiaryEvidenceRef;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 그림일기 V2 구조화 항목의 근거 참조를 담당한다. */
public interface ReportDiaryEvidenceRefRepository
    extends JpaRepository<ReportDiaryEvidenceRef, Long> {

  /**
   * 리포트의 근거 참조를 소유 항목·순서대로 읽는다. 호출부가 owner 로 묶어 쓴다.
   *
   * @param reportId 리포트 식별자
   * @return 순서대로 정렬된 목록이며 없으면 빈 목록
   */
  List<ReportDiaryEvidenceRef> findByReportIdOrderByOwnerTypeAscOwnerOrderAscDisplayOrderAsc(
      Long reportId);
}
