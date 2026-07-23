package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import java.time.Instant;

/**
 * 그림 활동 상세에서 공개할 최신 분석 실행 Metadata다.
 *
 * @param drawingAnalysisId 분석 실행 식별자
 * @param analysisScope 중간 또는 최종 분석 범위
 * @param analysisType AI 작업 유형
 * @param analysisStatus 현재 분석 처리 상태
 * @param requestedAt 분석 요청 시각
 * @param completedAt 분석 완료 시각, 완료 전이면 {@code null}
 */
public record DrawingSessionAnalysisSummaryResponse(
    Long drawingAnalysisId,
    DrawingAnalysisScope analysisScope,
    DrawingAnalysisType analysisType,
    DrawingAnalysisState analysisStatus,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant requestedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant completedAt) {}
