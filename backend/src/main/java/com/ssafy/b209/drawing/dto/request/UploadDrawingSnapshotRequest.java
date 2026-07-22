package com.ssafy.b209.drawing.dto.request;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.time.OffsetDateTime;

/**
 * 그림 스냅샷 파일과 함께 전달되는 캡처 Metadata다.
 *
 * @param assetType 중간 또는 최종 그림 파일 유형
 * @param assetVersion 세션과 유형 안에서 사용하는 양의 버전
 * @param capturedAt Offset을 포함한 클라이언트 캡처 시각
 */
public record UploadDrawingSnapshotRequest(
    @NotNull DrawingAssetType assetType,
    @NotNull @Positive Integer assetVersion,
    @NotNull OffsetDateTime capturedAt) {}
