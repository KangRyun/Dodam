package com.ssafy.b209.drawing.dto.request;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.util.List;

/**
 * 그림 활동 중 발생한 단일 Stroke 또는 편집 행위를 전달한다.
 *
 * @param sequence 세션 전체에서 증가하는 이벤트 순번
 * @param eventType 이벤트 유형 코드
 * @param tool 그리기 도구 코드
 * @param color RGB 또는 RGBA Hex 색상
 * @param width 선 굵기
 * @param pressure 이벤트 대표 필압
 * @param points 이벤트 내부 좌표 목록
 */
public record StrokeEventRequest(
    @Positive long sequence,
    @NotBlank @Size(max = 30) @Pattern(regexp = "[A-Z][A-Z0-9_]*") String eventType,
    @Size(max = 30) @Pattern(regexp = "[A-Z][A-Z0-9_]*") String tool,
    @Pattern(regexp = "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$") String color,
    @DecimalMin(value = "0.0", inclusive = false) BigDecimal width,
    @DecimalMin("0.0") @DecimalMax("1.0") BigDecimal pressure,
    @NotNull @Size(max = 10000) List<@Valid StrokePointRequest> points) {}
