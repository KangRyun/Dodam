package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import java.time.Instant;

/**
 * 저장되었거나 가장 최근인 그림 초안의 공개 가능한 Metadata다.
 *
 * <p>이미지 다운로드 API가 마련되기 전까지 내부 Storage Key와 임의 URL을 반환하지 않는다.
 *
 * @param drawingAssetId 그림 파일 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param assetType 항상 {@link DrawingAssetType#DRAFT}
 * @param assetVersion 서버가 초안 저장 순서에 따라 부여한 버전
 * @param lastEventSequence 초안에 반영된 마지막 그림 이벤트 순서
 * @param finalSnapshot 최종 그림이 아니므로 항상 {@code false}
 * @param contentType 실제 파일 Signature로 검증된 MIME Type
 * @param fileSize 실제 저장된 파일 크기(Byte)
 * @param clientSavedAt 클라이언트 저장 시각
 * @param savedAt 서버 저장 시각
 * @param expiresAt 만료 정책이 없으므로 현재 {@code null}
 * @param previewUrl 이미지 다운로드 API가 없어 현재 {@code null}
 * @param canvasState 초안과 그림 이벤트를 맞추기 위한 최소 복구 기준
 */
public record DrawingDraftResponse(
    Long drawingAssetId,
    Long drawingSessionId,
    DrawingAssetType assetType,
    int assetVersion,
    long lastEventSequence,
    boolean finalSnapshot,
    String contentType,
    long fileSize,
    Instant clientSavedAt,
    Instant savedAt,
    Instant expiresAt,
    String previewUrl,
    DrawingCanvasStateResponse canvasState) {}
