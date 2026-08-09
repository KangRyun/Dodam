package com.ssafy.b209.report.repository;

import com.ssafy.b209.report.domain.ReportDetectedObjectView;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** REPORT-02 보호자용 그림 심리 상담 리포트 상세 조회에서 탐지 객체명을 읽는 저장소다. */
public interface ReportDetectedObjectViewRepository
    extends JpaRepository<ReportDetectedObjectView, Long> {

  /**
   * 리포트가 가리키는 활동에서 탐지된 객체를 한 번의 조회로 모두 읽는다.
   *
   * <p>탐지 결과는 리포트 생성 분석({@code ACTIVITY_REPORT})이 아니라 세션별 객체 탐지 분석에 쌓이므로, 리포트 분석 식별자가 아니라 활동 세션을
   * 기준으로 찾는다. 집·나무·사람 활동이면 같은 묶음의 세 세션을 모두 대상으로 삼고, 그 외 활동은 대상 세션 하나만 본다. 대상 세션은 하위 Query에서 {@code
   * htp_assessment_steps}를 왼쪽 Join 해 한 번에 확정하므로 세션 수만큼 조회를 반복하지 않는다.
   *
   * <p>탐지 출처는 그리는 중 초안이 최종 결과를 가리지 않도록 {@code FINAL} 범위의 성공한 객체 탐지 분석으로 한정한다. 한 세션에 재시도 등으로 여러 건이
   * 있을 수 있어 요청 시각과 식별자 역순으로 정렬해 두고, 세션마다 첫 분석만 사용하는 판정은 호출 측에서 한다.
   *
   * @param drawingSessionId 리포트 대상 그림 활동 세션 식별자
   * @return 주제 순서, 세션, 분석 최신순, 탐지 순서로 정렬된 탐지 객체 목록
   */
  @Query(
      "select new com.ssafy.b209.report.repository.ReportDetectedObjectRow("
          + "analysis.drawingSessionId, analysis.id, detected.objectName, detected.confidenceScore) "
          + "from ReportDetectedObjectView detected "
          + "join ReportAnalysisView analysis on analysis.id = detected.analysisId "
          + "left join ReportHtpStepView step on step.drawingSessionId = analysis.drawingSessionId "
          + "where analysis.drawingSessionId in ("
          + "select coalesce(sibling.drawingSessionId, target.id) "
          + "from ReportDrawingSessionView target "
          + "left join ReportHtpStepView self on self.drawingSessionId = target.id "
          + "left join ReportHtpStepView sibling on sibling.assessmentId = self.assessmentId "
          + "where target.id = :drawingSessionId) "
          + "and analysis.scope = com.ssafy.b209.analysis.domain.DrawingAnalysisScope.FINAL "
          + "and analysis.taskType = com.ssafy.b209.analysis.dto.DrawingAnalysisType.OBJECT_DETECTION "
          + "and analysis.state in (com.ssafy.b209.analysis.domain.DrawingAnalysisState.SUCCESS, "
          + "com.ssafy.b209.analysis.domain.DrawingAnalysisState.PARTIAL_SUCCESS) "
          + "order by coalesce(step.stepOrder, 1) asc, analysis.drawingSessionId asc, "
          + "analysis.requestedAt desc, analysis.id desc, "
          + "detected.detectionOrder asc, detected.id asc")
  List<ReportDetectedObjectRow> findActivityDetectedObjects(
      @Param("drawingSessionId") Long drawingSessionId);
}
