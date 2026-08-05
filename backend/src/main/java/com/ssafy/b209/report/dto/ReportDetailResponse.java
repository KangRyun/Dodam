package com.ssafy.b209.report.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.LocalDateTime;
import java.util.List;

/**
 * REPORT-02 보호자용 관찰 리포트 상세 조회 응답이다.
 *
 * <p>보호자 안전 규칙에 따라 AI 추정 감정·확률, 위험도, 보호자에게 열리지 않은 관찰 특징({@code EXPERT_ONLY}), 내부 지표는 포함하지 않는다.
 *
 * @param reportId 리포트 식별자
 * @param reportVersion 리포트 버전
 * @param reportStatus 리포트 생성 상태
 * @param drawingSession 그림 활동 세션 요약
 * @param drawing 그림 이미지 URL
 * @param childExpression 아동 표현
 * @param observedFeatures 검토를 통과해 보호자에게 열린 관찰 특징 목록이며 없으면 빈 목록. {@code EXPERT_ONLY} 항목은 담기지 않는다
 * @param activityFacts 활동 사실 기록
 * @param conversationSummary 대화 요약
 * @param guardianConversationGuide 보호자 후속 대화 안내 목록
 * @param limitations 리포트 해석 시 적용할 한계·주의 문구 목록
 * @param expertReview 전문가 검토 상태
 * @param createdAt 리포트 생성 시각
 */
@Schema(description = "보호자용 관찰 리포트 상세")
public record ReportDetailResponse(
    Long reportId,
    int reportVersion,
    String reportStatus,
    ReportDrawingSessionResponse drawingSession,
    ReportDrawingResponse drawing,
    ReportChildExpressionResponse childExpression,
    List<ReportObservedFeatureResponse> observedFeatures,
    ReportActivityFactsResponse activityFacts,
    ReportConversationSummaryResponse conversationSummary,
    List<String> guardianConversationGuide,
    List<String> limitations,
    ReportExpertReviewResponse expertReview,
    LocalDateTime createdAt,
    String nonDiagnosticNotice,
    List<ReportPublicInterpretationResponse> publicInterpretations,
    List<ReportEvidenceItemResponse> evidenceItems,
    List<ReportSubjectResponse> subjectReports,
    List<ReportParentGuideResponse> parentGuides,
    ReportCrisisAlertResponse crisisAlert,
    List<ReportReferenceResponse> references) {

  /**
   * 관찰 특징까지만 있던 형태로 만든다 (S15P11B209-931).
   *
   * <p>931 이 {@code observedFeatures} 를 추가한 시점의 호출부를 그대로 두기 위한 생성자다. 902 가 더한 경향 해석·근거·주제별·가이드는 빈
   * 목록, 위기 안내는 {@code null} 로 둔다 — 875 §10 대로 빈 섹션은 오류가 아니라 정상이다.
   *
   * @param reportId 리포트 식별자
   * @param reportVersion 리포트 버전
   * @param reportStatus 리포트 상태
   * @param drawingSession 그림 활동 세션 요약
   * @param drawing 그림 URL 묶음
   * @param childExpression 아이 표현 요약
   * @param observedFeatures 보호자에게 열린 관찰 특징 목록
   * @param activityFacts 객관 활동 기록
   * @param conversationSummary 대화 요약
   * @param guardianConversationGuide 보호자 대화 안내 목록
   * @param limitations 한계 문구 목록
   * @param expertReview 전문가 검토 상태
   * @param createdAt 생성 시각
   */
  public ReportDetailResponse(
      Long reportId,
      int reportVersion,
      String reportStatus,
      ReportDrawingSessionResponse drawingSession,
      ReportDrawingResponse drawing,
      ReportChildExpressionResponse childExpression,
      List<ReportObservedFeatureResponse> observedFeatures,
      ReportActivityFactsResponse activityFacts,
      ReportConversationSummaryResponse conversationSummary,
      List<String> guardianConversationGuide,
      List<String> limitations,
      ReportExpertReviewResponse expertReview,
      LocalDateTime createdAt) {
    this(
        reportId,
        reportVersion,
        reportStatus,
        drawingSession,
        drawing,
        childExpression,
        observedFeatures,
        activityFacts,
        conversationSummary,
        guardianConversationGuide,
        limitations,
        expertReview,
        createdAt,
        NON_DIAGNOSTIC_NOTICE,
        List.of(),
        List.of(),
        List.of(),
        List.of(),
        null,
        List.of());
  }

  /**
   * 875 확장 이전 형태로 만든다.
   *
   * <p>신규 섹션이 없던 호출부(주로 테스트)를 그대로 두기 위한 생성자다. 신규 배열은 빈 목록, 위기 안내는 {@code null}(신호 없음)로 둔다 — 875 §10
   * 대로 빈 섹션은 오류가 아니라 정상이다.
   *
   * @param reportId 리포트 식별자
   * @param reportVersion 리포트 버전
   * @param reportStatus 리포트 상태
   * @param drawingSession 그림 활동 세션 요약
   * @param drawing 그림 URL 묶음
   * @param childExpression 아이 표현 요약
   * @param activityFacts 객관 활동 기록
   * @param conversationSummary 대화 요약
   * @param guardianConversationGuide 보호자 대화 안내 목록
   * @param limitations 한계 문구 목록
   * @param expertReview 전문가 검토 상태
   * @param createdAt 생성 시각
   */
  public ReportDetailResponse(
      Long reportId,
      int reportVersion,
      String reportStatus,
      ReportDrawingSessionResponse drawingSession,
      ReportDrawingResponse drawing,
      ReportChildExpressionResponse childExpression,
      ReportActivityFactsResponse activityFacts,
      ReportConversationSummaryResponse conversationSummary,
      List<String> guardianConversationGuide,
      List<String> limitations,
      ReportExpertReviewResponse expertReview,
      LocalDateTime createdAt) {
    this(
        reportId,
        reportVersion,
        reportStatus,
        drawingSession,
        drawing,
        childExpression,
        // 관찰 특징은 이 구 생성자를 쓰는 경로가 채우지 않는다 — 빈 목록이면 섹션이 숨는다(계약 §10).
        List.of(),
        activityFacts,
        conversationSummary,
        guardianConversationGuide,
        limitations,
        expertReview,
        createdAt,
        NON_DIAGNOSTIC_NOTICE,
        List.of(),
        List.of(),
        List.of(),
        List.of(),
        null,
        List.of());
  }

  /**
   * 보호자 리포트가 진단이 아님을 알리는 고정 문구다 (875 §2).
   *
   * <p>AI 가 만들지 않는다 — 문구가 흔들리면 같은 리포트가 어떤 날은 진단처럼 읽힌다.
   */
  public static final String NON_DIAGNOSTIC_NOTICE =
      "이 리포트는 아이가 그림을 그리고 대화한 과정에서 나타난 특징과 심리적 경향을 정리한 자료입니다."
          + " 아이의 평소 성격이나 심리 상태를 확정하거나 진단하는 결과는 아닙니다.";
}
