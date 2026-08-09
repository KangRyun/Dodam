package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDrawnItem;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 '그린 것' 항목을 저장·조회하는 저장소다 (S15P11B209-912). */
public interface ReportDrawnItemRepository extends JpaRepository<ReportDrawnItem, Long> {

  /**
   * 리포트의 '그린 것' 항목을 노출 순서대로 조회한다.
   *
   * <p>정렬은 성능 옵션이 아니라 계약이다 — 화면과 PDF 가 이 순서로 이어 붙여 한 문장을 만들므로 순서가 바뀌면 문장이 달라진다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 오름차순 항목 목록
   */
  List<ReportDrawnItem> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
