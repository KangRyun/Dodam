package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.analysis.dto.DrawingAnalysisStatus;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;

/**
 * 그림 단계 완료 과정에서 실행한 대화 준비용 분석 상태다.
 *
 * @param analysisId 분석 실행 식별자
 * @param analysisType 수행한 분석 작업 유형
 * @param status 외부 API에 노출하는 분석 처리 상태
 */
public record DrawingStageAnalysisResponse(
    Long analysisId, DrawingAnalysisType analysisType, DrawingAnalysisStatus status) {}
