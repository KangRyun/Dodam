package com.ssafy.b209.analysis.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

/**
 * AI 서버가 그림에서 탐지한 단일 객체의 계약이다.
 *
 * <p>객체 Label 정책이 확정되지 않았으므로 {@code label}은 Enum 대신 문자열로 유지한다.
 *
 * @param label 탐지된 객체를 나타내는 비어 있지 않은 Label
 * @param confidence 탐지 신뢰도(0 이상 1 이하)
 * @param boundingBox 원본 이미지 픽셀 기준 객체 영역
 */
public record DrawingDetectionResponse(
    @NotBlank String label,
    @NotNull @DecimalMin("0.0") @DecimalMax("1.0") BigDecimal confidence,
    @NotNull @Valid BoundingBoxResponse boundingBox) {}
