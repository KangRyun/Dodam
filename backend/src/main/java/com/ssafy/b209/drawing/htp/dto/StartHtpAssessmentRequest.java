package com.ssafy.b209.drawing.htp.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.dto.request.CanvasConfigurationRequest;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.OffsetDateTime;

/**
 * HTP 활동과 첫 HOUSE 그림 세션을 함께 시작하는 요청이다.
 *
 * @param childId HTP 활동을 수행할 아동 식별자
 * @param inputMethod 첫 단계와 후속 단계에 공통 적용할 그림 입력 방식
 * @param clientStartedAt 클라이언트가 관찰한 시작 시각
 * @param canvas 선택적으로 전달하는 캔버스 설정
 */
public record StartHtpAssessmentRequest(
    @Schema(description = "HTP 활동을 수행할 아동 식별자", example = "1") @NotNull @Positive Long childId,
    @Schema(description = "그림 입력 방식", example = "CANVAS") @NotNull DrawingInputMethod inputMethod,
    @Schema(description = "클라이언트가 관찰한 시작 시각", example = "2026-07-28T10:00:00+09:00")
        @NotNull
        @JsonFormat(shape = JsonFormat.Shape.STRING)
        OffsetDateTime clientStartedAt,
    CanvasConfigurationRequest canvas) {}
