package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
import java.time.Instant;

/**
 * 그림 활동 상세에서 공개하는 최신 그림 파일 Metadata다.
 *
 * <p>이미지 크기는 실제 파일 Header를 기준으로 하며, 변경 전 생성된 기존 Asset은 {@code null}일 수 있다.
 *
 * @param drawingAssetId 그림 파일 식별자
 * @param assetType 그림 파일 용도
 * @param assetVersion 세션과 용도 안에서 증가하는 버전
 * @param mimeType 검증된 이미지 MIME Type
 * @param fileSizeBytes 실제 파일 크기(Byte)
 * @param widthPx 실제 저장 이미지 너비(px)
 * @param heightPx 실제 저장 이미지 높이(px)
 * @param capturedAt 클라이언트가 이미지를 저장한 시각
 * @param createdAt 서버가 Metadata를 생성한 시각
 */
public record DrawingSessionAssetSummaryResponse(
    Long drawingAssetId,
    DrawingAssetType assetType,
    int assetVersion,
    String mimeType,
    long fileSizeBytes,
    Integer widthPx,
    Integer heightPx,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant capturedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant createdAt) {

  /** 이미지 크기 필드가 추가되기 전 응답을 구성하는 호환 생성자다. */
  public DrawingSessionAssetSummaryResponse(
      Long drawingAssetId,
      DrawingAssetType assetType,
      int assetVersion,
      String mimeType,
      long fileSizeBytes,
      Instant capturedAt,
      Instant createdAt) {
    this(
        drawingAssetId,
        assetType,
        assetVersion,
        mimeType,
        fileSizeBytes,
        null,
        null,
        capturedAt,
        createdAt);
  }
}
