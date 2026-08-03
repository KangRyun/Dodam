package com.ssafy.b209.community.dto;

import com.ssafy.b209.community.domain.CommunityAttachmentType;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * 게시글에 연결할 사전 업로드 첨부 파일 참조다.
 *
 * @param fileId 사전 업로드 API가 발급한 파일 ID
 * @param type 첨부 유형이며 현재는 {@code IMAGE}만 허용
 */
@Schema(description = "커뮤니티 게시글 첨부 파일 참조")
public record CommunityAttachmentInput(
    @Schema(description = "사전 업로드 API가 발급한 파일 ID") @NotBlank @Size(max = 36) String fileId,
    @Schema(description = "첨부 유형") @NotNull CommunityAttachmentType type) {}
