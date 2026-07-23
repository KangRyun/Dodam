package com.ssafy.b209.analysis.dto;

import jakarta.validation.constraints.NotNull;

/**
 * 실패한 그림 분석을 다시 요청할 때 사용할 입력 선택 정책이다.
 *
 * @param reason 사용자가 재시도를 요청한 사유
 * @param useLatestInputs 같은 세션·자산 유형의 최신 그림을 사용할지 여부
 */
public record RetryDrawingAnalysisRequest(
    @NotNull DrawingAnalysisRetryReason reason, @NotNull Boolean useLatestInputs) {}
