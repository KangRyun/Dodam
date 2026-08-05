package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.domain.ReportObservedFeatureView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 보호자에게 열린 관찰 특징만 읽는 저장소다. */
public interface ReportObservedFeatureViewRepository
    extends JpaRepository<ReportObservedFeatureView, Long> {

  /**
   * 리포트의 관찰 특징 중 지정한 노출 범위인 것만 노출 순서 오름차순으로 조회한다.
   *
   * <p>보호자 경로는 항상 {@link ReportFeatureVisibility#REVIEWED_GUARDIAN} 만 넘긴다. 범위를 인자로 받는 이유는 조건을 호출부에
   * 드러내 "무엇을 열고 있는지"가 조회 지점에서 보이게 하기 위해서다.
   *
   * @param reportId 리포트 식별자
   * @param visibilityScope 조회할 노출 범위
   * @return 노출 순서 오름차순으로 정렬된 관찰 특징 목록
   */
  List<ReportObservedFeatureView> findByReportIdAndVisibilityScopeOrderByDisplayOrderAsc(
      Long reportId, ReportFeatureVisibility visibilityScope);
}
