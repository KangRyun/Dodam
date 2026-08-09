package com.ssafy.b209.drawing.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import java.math.BigDecimal;

/**
 * 캔버스 크기와 무관한 정규화 좌표 한 점을 전달한다.
 *
 * @param x 0 이상 1 이하의 X 좌표
 * @param y 0 이상 1 이하의 Y 좌표
 * @param t 이벤트 시작 후 경과 시간(ms)
 * @param pressure 기기가 제공한 필압, 지원하지 않으면 {@code null}
 */
public record StrokePointRequest(
    @Schema(description = "0 이상 1 이하의 X 정규화 좌표", example = "0.18")
        @NotNull
        @DecimalMin("0.0")
        @DecimalMax("1.0")
        BigDecimal x,
    @Schema(description = "0 이상 1 이하의 Y 정규화 좌표", example = "0.42")
        @NotNull
        @DecimalMin("0.0")
        @DecimalMax("1.0")
        BigDecimal y,
    @Schema(description = "이벤트 시작 후 경과 시간(ms)", example = "0") @PositiveOrZero long t,
    @Schema(description = "기기가 제공한 필압, 미지원 시 null") @DecimalMin("0.0") @DecimalMax("1.0")
        BigDecimal pressure) {}
