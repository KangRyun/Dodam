package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDrawingEmotionView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

/** REPORT-02 보호자용 리포트 상세 조회에서 아동이 선택한 감정을 읽는 저장소다. */
public interface ReportDrawingEmotionViewRepository
    extends JpaRepository<ReportDrawingEmotionView, Long> {

  /**
   * 세션의 선택 감정을 선택 순서 오름차순으로 조회한다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 선택 순서 오름차순으로 정렬된 감정 목록
   */
  List<ReportDrawingEmotionView> findByDrawingSessionIdOrderBySelectionOrderAsc(
      Long drawingSessionId);
}
