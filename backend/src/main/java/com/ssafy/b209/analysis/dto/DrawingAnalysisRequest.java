package com.ssafy.b209.analysis.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * Spring Boot가 AI 서버에 전달하는 그림 분석 요청 계약이다.
 *
 * <p>그림 도메인의 Entity 대신 식별자와 저장소 참조만 전달하며, 개인정보와 이미지 원문은 포함하지 않는다.
 *
 * @param requestId 호출 추적과 후속 응답 연결에 사용하는 요청 식별자
 * @param drawingSessionId 분석 대상 그림 활동 세션 ID
 * @param drawingAssetId 분석 대상 그림 파일 Metadata ID
 * @param imageReference 분석할 그림의 내부 저장소 참조
 * @param analysisType 수행할 AI 분석 유형
 */
public record DrawingAnalysisRequest(
    @NotBlank String requestId,
    @NotNull @Positive Long drawingSessionId,
    @NotNull @Positive Long drawingAssetId,
    @NotNull @Valid DrawingImageReference imageReference,
    @NotNull DrawingAnalysisType analysisType) {}
