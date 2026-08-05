package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportInterpretationDisclosureState;
import com.ssafy.b209.report.domain.ReportPublicInterpretation;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** 리포트 경향 해석 카드를 저장·조회하는 저장소다. */
public interface ReportPublicInterpretationRepository
    extends JpaRepository<ReportPublicInterpretation, Long> {

  /**
   * 리포트의 경향 해석을 노출 순서대로 조회한다.
   *
   * <p>순서가 곧 응답 배열 인덱스이자 {@code interpretationRefs} 의 참조 대상이므로 정렬 없이 읽지 않는다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 오름차순 경향 해석 목록
   */
  List<ReportPublicInterpretation> findByReportIdOrderByDisplayOrderAsc(Long reportId);

  /**
   * 리포트에서 지정한 공개 상태인 경향 해석만 노출 순서대로 조회한다.
   *
   * @param reportId 리포트 식별자
   * @param disclosureState 조회할 공개 판정 결과
   * @return 노출 순서 오름차순 경향 해석 목록
   */
  List<ReportPublicInterpretation> findByReportIdAndDisclosureStateOrderByDisplayOrderAsc(
      Long reportId, ReportInterpretationDisclosureState disclosureState);
}
