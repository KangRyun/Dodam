package com.ssafy.b209.analysis.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

/**
 * 탐지된 객체가 원본 이미지에서 차지하는 픽셀 좌표 영역이다.
 *
 * <p>좌측 상단을 원점으로 하며, 기존 대화 계약에서 사용하는 0~1 정규화 좌표와 호환되는 타입이 아니다.
 *
 * @param x 좌측 상단의 X 픽셀 좌표
 * @param y 좌측 상단의 Y 픽셀 좌표
 * @param width 객체 영역의 픽셀 너비
 * @param height 객체 영역의 픽셀 높이
 */
public record BoundingBoxResponse(
    @NotNull @DecimalMin("0.0") BigDecimal x,
    @NotNull @DecimalMin("0.0") BigDecimal y,
    @NotNull @DecimalMin(value = "0.0", inclusive = false) BigDecimal width,
    @NotNull @DecimalMin(value = "0.0", inclusive = false) BigDecimal height) {}
