package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportReference;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 참고 자료를 저장·조회하는 저장소다 (S15P11B209-960, 875 §9). */
public interface ReportReferenceRepository extends JpaRepository<ReportReference, Long> {

  /**
   * 리포트의 참고 자료를 노출 순서대로 조회한다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 오름차순 참고 자료 목록
   */
  List<ReportReference> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
