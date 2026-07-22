package com.ssafy.b209.analysis.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * 저장된 그림 파일에 새 분석 실행을 요청하는 공개 API 입력이다.
 *
 * @param drawingAssetId 분석 대상 그림 파일 Metadata 식별자
 * @param analysisType 수행할 AI 분석 작업 유형
 */
public record CreateDrawingAnalysisRequest(
    @NotNull @Positive Long drawingAssetId, @NotNull DrawingAnalysisType analysisType) {}
