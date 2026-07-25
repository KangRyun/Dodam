package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingAssetType;
import java.time.Instant;

/**
 * 저장된 그림 스냅샷의 공개 가능한 Metadata다.
 *
 * <p>Storage Key와 서버 내부 경로는 노출하지 않는다. 이미지 크기는 업로드된 실제 파일 Header를 기준으로 한다.
 *
 * @param drawingAssetId 그림 파일 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param assetType 그림 파일 용도
 * @param assetVersion 세션과 유형 안에서 증가하는 버전
 * @param mimeType 검증된 이미지 MIME Type
 * @param fileSizeBytes 실제 파일 크기(Byte)
 * @param widthPx 실제 저장 이미지 너비(px)
 * @param heightPx 실제 저장 이미지 높이(px)
 * @param checksumSha256 실제 이미지 Byte의 SHA-256 Hex
 * @param capturedAt 클라이언트가 이미지를 캡처한 시각
 * @param uploadedAt 서버가 저장을 완료한 시각
 */
public record UploadDrawingSnapshotResponse(
    Long drawingAssetId,
    Long drawingSessionId,
    DrawingAssetType assetType,
    int assetVersion,
    String mimeType,
    long fileSizeBytes,
    Integer widthPx,
    Integer heightPx,
    String checksumSha256,
    Instant capturedAt,
    Instant uploadedAt) {

  /** 이미지 크기 필드가 추가되기 전 응답을 구성하는 호환 생성자다. */
  public UploadDrawingSnapshotResponse(
      Long drawingAssetId,
      Long drawingSessionId,
      DrawingAssetType assetType,
      int assetVersion,
      String mimeType,
      long fileSizeBytes,
      String checksumSha256,
      Instant capturedAt,
      Instant uploadedAt) {
    this(
        drawingAssetId,
        drawingSessionId,
        assetType,
        assetVersion,
        mimeType,
        fileSizeBytes,
        null,
        null,
        checksumSha256,
        capturedAt,
        uploadedAt);
  }
}
