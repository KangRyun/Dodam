package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import java.time.Instant;

/**
 * 저장된 그림 스냅샷의 공개 가능한 Metadata다.
 *
 * <p>서버 내부 Storage Key, 절대 경로와 원본 파일명은 노출하지 않는다.
 *
 * @param drawingAssetId 그림 파일 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param assetType 그림 파일 용도
 * @param assetVersion 세션과 유형 안에서의 버전
 * @param mimeType 실제 파일 Signature로 검증된 MIME Type
 * @param fileSizeBytes 실제 저장된 파일 크기(Byte)
 * @param checksumSha256 실제 저장된 Byte의 SHA-256 Hex
 * @param capturedAt 클라이언트 캡처 시각
 * @param uploadedAt 서버 저장 시각
 */
public record UploadDrawingSnapshotResponse(
    Long drawingAssetId,
    Long drawingSessionId,
    DrawingAssetType assetType,
    int assetVersion,
    String mimeType,
    long fileSizeBytes,
    String checksumSha256,
    Instant capturedAt,
    Instant uploadedAt) {}
