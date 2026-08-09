package com.ssafy.b209.drawing.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import java.time.OffsetDateTime;

/**
 * 그림 단계 완료 파일과 함께 전달되는 클라이언트 Metadata다.
 *
 * @param sourceAssetId 이미 저장된 FINAL 그림 파일을 재사용할 때 지정하는 식별자
 * @param lastEventSequence 최종 이미지에 반영된 마지막 그림 이벤트 순번
 * @param drawingDurationMs 그림 작성에 사용한 시간(ms)
 * @param clientCompletedAt 클라이언트가 최종 이미지를 확정한 Offset 포함 시각
 */
public record CompleteDrawingStageRequest(
    @Schema(description = "재사용할 동일 세션 FINAL 그림 파일 식별자", example = "502") @Positive
        Long sourceAssetId,
    @Schema(description = "최종 이미지에 반영된 마지막 그림 이벤트 순번", example = "150") @PositiveOrZero
        Long lastEventSequence,
    @Schema(description = "그림 작성 시간(ms)", example = "120000") @NotNull @Positive
        Long drawingDurationMs,
    @Schema(description = "Offset을 포함한 클라이언트 완료 시각", example = "2026-07-25T19:30:00+09:00") @NotNull
        OffsetDateTime clientCompletedAt) {}
