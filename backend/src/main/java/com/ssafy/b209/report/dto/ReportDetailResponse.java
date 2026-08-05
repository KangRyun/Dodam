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
    LocalDateTime createdAt) {}
