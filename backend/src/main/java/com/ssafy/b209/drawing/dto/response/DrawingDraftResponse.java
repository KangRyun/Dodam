package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import java.time.Instant;

/**
 * 저장됐거나 조회된 최신 그림 초안의 공개 가능한 Metadata다.
 *
 * <p>이미지 크기는 실제 저장 파일에서 수집하며, 변경 전 생성된 기존 Asset은 {@code null}일 수 있다.
 *
 * @param drawingAssetId 그림 파일 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param assetType 항상 {@link DrawingAssetType#DRAFT}
 * @param assetVersion 서버가 초안 저장 순서에 따라 부여한 버전
 * @param lastEventSequence 초안에 반영된 마지막 그림 이벤트 순서
 * @param finalSnapshot 최종 그림 여부이며 초안에서는 {@code false}
 * @param contentType 검증된 이미지 MIME Type
 * @param fileSize 실제 저장 파일 크기(Byte)
 * @param widthPx 실제 저장 이미지 너비(px)
 * @param heightPx 실제 저장 이미지 높이(px)
 * @param clientSavedAt 클라이언트가 저장한 시각
 * @param savedAt 서버가 저장한 시각
 * @param expiresAt 만료 정책이 없다면 {@code null}
 * @param previewUrl JWT 인증과 함께 호출하는 그림 파일 상대 조회 URL
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
    Integer widthPx,
    Integer heightPx,
    Instant clientSavedAt,
    Instant savedAt,
    Instant expiresAt,
    String previewUrl,
    DrawingCanvasStateResponse canvasState) {

  /** 이미지 크기 필드가 추가되기 전 응답을 구성하는 호환 생성자다. */
  public DrawingDraftResponse(
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
      DrawingCanvasStateResponse canvasState) {
    this(
        drawingAssetId,
        drawingSessionId,
        assetType,
        assetVersion,
        lastEventSequence,
        finalSnapshot,
        contentType,
        fileSize,
        null,
        null,
        clientSavedAt,
        savedAt,
        expiresAt,
        previewUrl,
        canvasState);
  }
}
