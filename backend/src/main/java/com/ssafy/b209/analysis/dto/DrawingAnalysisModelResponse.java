package com.ssafy.b209.analysis.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 그림 분석에 사용된 AI 모델의 식별 정보다.
 *
 * @param name 모델 이름
 * @param version 재현 가능한 모델 버전
 */
public record DrawingAnalysisModelResponse(@NotBlank String name, @NotBlank String version) {}
