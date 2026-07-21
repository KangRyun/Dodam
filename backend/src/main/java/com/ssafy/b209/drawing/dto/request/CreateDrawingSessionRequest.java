package com.ssafy.b209.drawing.dto.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.OffsetDateTime;

/**
 * 그림 활동 세션 생성을 요청하는 입력값이며, clientStartedAt은 관찰된 클라이언트 시각이다.
 *
 * @param childId 그림 활동을 시작할 아동 식별자
 * @param drawingTypeId 선택한 그림 활동 유형 식별자
 * @param inputMethod 그림 입력 방식
 * @param clientStartedAt 클라이언트가 관찰한 시작 시각
 * @param canvas 선택적으로 전달하는 캔버스 설정
 */
public record CreateDrawingSessionRequest(
    @NotNull @Positive Long childId,
    @NotNull @Positive Long drawingTypeId,
    @NotNull DrawingInputMethod inputMethod,
    @NotNull @JsonFormat(shape = JsonFormat.Shape.STRING) OffsetDateTime clientStartedAt,
    CanvasConfigurationRequest canvas) {}
