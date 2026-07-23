package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.time.Instant;

/**
 * 진행 중 그림 활동 재개에 필요한 최신 자동 저장 초안의 공개 가능한 Metadata다.
 *
 * <p>이미지 다운로드 API가 마련되기 전까지 내부 Storage Key와 임의 URL을 노출하지 않는다.
 *
 * @param drawingAssetId 그림 초안 파일 식별자
 * @param assetVersion 서버가 초안 저장 순서에 따라 부여한 버전
 * @param lastEventSequence 초안에 반영된 마지막 그림 이벤트 순서
 * @param contentType 실제 파일 Signature로 검증된 MIME Type
 * @param fileSize 실제 저장된 파일 크기(Byte)
 * @param clientSavedAt 클라이언트가 초안을 저장한 시각
 * @param savedAt 서버가 초안 Metadata를 저장한 시각
 * @param previewUrl 이미지 다운로드 API가 없어 현재 {@code null}
 */
public record LatestDrawingDraftResponse(
    Long drawingAssetId,
    int assetVersion,
    long lastEventSequence,
    String contentType,
    long fileSize,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant clientSavedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant savedAt,
    String previewUrl) {}
