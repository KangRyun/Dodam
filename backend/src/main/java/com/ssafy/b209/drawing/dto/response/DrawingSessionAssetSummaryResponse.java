package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import java.time.Instant;

/**
 * 그림 활동 상세에서 공개할 최신 그림 파일 Metadata다.
 *
 * <p>내부 저장 위치와 원본 파일 내용은 포함하지 않는다.
 *
 * @param drawingAssetId 그림 파일 식별자
 * @param assetType 그림 파일 용도
 * @param assetVersion 세션과 용도 안에서 증가하는 버전
 * @param mimeType 검증된 이미지 MIME Type
 * @param fileSizeBytes 파일 크기
 * @param capturedAt 클라이언트가 그림을 저장한 시각
 * @param createdAt 서버가 Metadata를 생성한 시각
 */
public record DrawingSessionAssetSummaryResponse(
    Long drawingAssetId,
    DrawingAssetType assetType,
    int assetVersion,
    String mimeType,
    long fileSizeBytes,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant capturedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant createdAt) {}
