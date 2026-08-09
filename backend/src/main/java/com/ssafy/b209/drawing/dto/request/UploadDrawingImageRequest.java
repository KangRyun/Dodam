package com.ssafy.b209.drawing.dto.request;

import com.fasterxml.jackson.annotation.JsonFormat;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import java.time.OffsetDateTime;

/**
 * 기존 이미지로 HTP 활동을 시작할 때 이미지와 함께 전달하는 Metadata다.
 *
 * @param clientCapturedAt 클라이언트가 이미지를 촬영하거나 선택한 시각, 알 수 없으면 {@code null}
 * @param rotationDegrees 업로드 전에 적용한 시계 방향 회전 각도
 * @param cropApplied 업로드 전에 사용자가 자르기를 적용했는지 여부
 */
public record UploadDrawingImageRequest(
    @Schema(description = "이미지 촬영 또는 선택 시각", nullable = true)
        @JsonFormat(shape = JsonFormat.Shape.STRING)
        OffsetDateTime clientCapturedAt,
    @Schema(description = "적용한 시계 방향 회전 각도", example = "0") Integer rotationDegrees,
    @Schema(description = "자르기 적용 여부", example = "true") @NotNull Boolean cropApplied) {

  /** 회전값이 생략되면 원본 방향을 뜻하는 0도로 정규화한다. */
  public UploadDrawingImageRequest {
    rotationDegrees = rotationDegrees == null ? 0 : rotationDegrees;
  }
}
