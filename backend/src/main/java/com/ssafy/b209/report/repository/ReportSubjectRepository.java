package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportSubject;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 주제별 관찰 묶음을 저장·조회하는 저장소다 (S15P11B209-960). */
public interface ReportSubjectRepository extends JpaRepository<ReportSubject, Long> {

  /**
   * 리포트의 주제별 관찰을 노출 순서대로 조회한다.
   *
   * <p><strong>정렬은 성능 옵션이 아니라 계약이다</strong> — 875 §5 가 {@code HOUSE → TREE → PERSON} 순서를 보장하므로 정렬
   * 없이 읽으면 계약을 깬다.
   *
   * <p>하위 목록(관찰 서술·문답·경향 해석 참조)은 지연 로딩으로 둔다. 셋 다 {@code List}라 한 쿼리로 함께 Fetch 하면 {@code
   * MultipleBagFetchException}이고, 주제는 리포트당 최대 3건이라 지연 로딩 비용이 문제가 되지 않는다. 조회는 읽기 전용 Transaction 안에서
   * 일어나므로 Session 이 열려 있다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 오름차순 주제별 관찰 목록
   */
  List<ReportSubject> findByReportIdOrderByDisplayOrderAsc(Long reportId);
}
