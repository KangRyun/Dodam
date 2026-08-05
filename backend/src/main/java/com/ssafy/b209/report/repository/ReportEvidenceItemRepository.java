package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportEvidenceItem;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 근거를 저장·조회하는 저장소다. */
public interface ReportEvidenceItemRepository extends JpaRepository<ReportEvidenceItem, Long> {

  /**
   * 리포트의 근거를 번호 순으로 조회한다.
   *
   * @param reportId 리포트 식별자
   * @return 근거 번호 오름차순 목록
   */
  List<ReportEvidenceItem> findByReportIdOrderByEvidenceNumberAsc(Long reportId);

  /**
   * 리포트 안의 근거 번호로 한 건을 조회한다.
   *
   * <p>응답의 {@code evidenceId} 는 이 번호이므로, 참조 정합을 확인할 때 이 조회를 쓴다.
   *
   * @param reportId 리포트 식별자
   * @param evidenceNumber 리포트 안에서 유일한 근거 번호
   * @return 근거이며 없으면 빈 값
   */
  Optional<ReportEvidenceItem> findByReportIdAndEvidenceNumber(Long reportId, int evidenceNumber);
}
