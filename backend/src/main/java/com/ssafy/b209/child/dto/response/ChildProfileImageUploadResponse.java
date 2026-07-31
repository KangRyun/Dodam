package com.ssafy.b209.child.dto.response;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 사전 업로드된 아동 프로필 이미지의 연결 식별자와 검증된 Metadata다.
 *
 * @param profileImageFileId 아동 등록·수정 요청에 전달할 파일 식별자
 * @param contentType 실제 이미지 Signature로 확인한 MIME Type
 * @param fileSizeBytes 저장된 이미지 크기
 * @param widthPx 이미지 너비
 * @param heightPx 이미지 높이
 * @param expiresAt 아동과 연결되지 않은 임시 파일의 만료 시각
 */
public record ChildProfileImageUploadResponse(
    @Schema(example = "d20f42a9-6a55-4c91-b4b0-b6c79b8bd121") String profileImageFileId,
    @Schema(example = "image/png") String contentType,
    @Schema(example = "1048576") long fileSizeBytes,
    @Schema(example = "512") int widthPx,
    @Schema(example = "512") int heightPx,
    Instant expiresAt) {}
