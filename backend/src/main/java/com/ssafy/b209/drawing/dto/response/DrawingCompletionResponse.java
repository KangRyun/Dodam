package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.report.domain.ReportStatus;

/**
 * 그림 활동 완료 후속 작업의 접수 상태를 반환한다.
 *
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param sessionStatus 접수 직후 세션 처리 상태
 * @param currentStage 접수 직후 그림 활동 단계
 * @param analysisId 최종 분석 식별자
 * @param analysisStatus 최종 분석 처리 상태
 * @param reportId 생성 요청한 리포트 식별자
 * @param reportStatus 리포트 처리 상태
 */
public record DrawingCompletionResponse(
    Long drawingSessionId,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage,
    Long analysisId,
    DrawingAnalysisState analysisStatus,
    Long reportId,
    ReportStatus reportStatus) {}
