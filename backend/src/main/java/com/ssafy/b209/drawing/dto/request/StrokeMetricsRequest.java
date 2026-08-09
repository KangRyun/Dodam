package com.ssafy.b209.drawing.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.PositiveOrZero;

/**
 * 현재 배치에서 증가한 편집 행동 지표를 전달한다.
 *
 * @param undoCountDelta 실행 취소 증가량
 * @param redoCountDelta 다시 실행 증가량
 * @param eraseCountDelta 지우기 증가량
 * @param pauseDurationMsDelta 일시 정지 시간 증가량(ms)
 */
public record StrokeMetricsRequest(
    @Schema(description = "실행 취소 증가량", example = "0") @PositiveOrZero int undoCountDelta,
    @Schema(description = "다시 실행 증가량", example = "0") @PositiveOrZero int redoCountDelta,
    @Schema(description = "지우기 증가량", example = "0") @PositiveOrZero int eraseCountDelta,
    @Schema(description = "일시 정지 시간 증가량(ms)", example = "0") @PositiveOrZero
        long pauseDurationMsDelta) {}
