package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;

/**
 * 멱등 요청 식별자로 저장된 그림 분석과 세션 상태를 Application 계층에 전달한다.
 *
 * @param analysisId 분석 실행 식별자
 * @param drawingSessionId 분석 대상 그림 활동 세션 식별자
 * @param drawingAssetId 분석 대상 그림 파일 식별자
 * @param taskType 수행한 분석 작업 유형
 * @param state DB에 저장된 분석 상태
 * @param sessionStatus 그림 활동 세션 처리 상태
 * @param currentStage 그림 활동의 현재 단계
 */
public record DrawingAnalysisRequestSummary(
    Long analysisId,
    Long drawingSessionId,
    Long drawingAssetId,
    DrawingAnalysisType taskType,
    DrawingAnalysisState state,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage) {}
