package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDrawingAssetView;
import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 그림 파일 식별 정보를 읽는 저장소다. */
public interface ReportDrawingAssetViewRepository
    extends JpaRepository<ReportDrawingAssetView, Long> {

  /**
   * 세션의 지정 유형 그림 파일을 버전 오름차순으로 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param assetTypes 조회할 파일 유형 코드 집합
   * @return 버전 오름차순으로 정렬된 그림 파일 목록
   */
  List<ReportDrawingAssetView> findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(
      Long drawingSessionId, Collection<String> assetTypes);
}
