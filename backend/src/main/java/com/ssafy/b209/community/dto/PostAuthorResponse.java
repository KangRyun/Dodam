package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 게시글 목록에서 공개 가능한 작성자 표시 정보다.
 *
 * @param userId 공개 가능한 작성자 사용자 ID
 * @param nickname 공개 가능한 작성자 닉네임
 */
@Schema(description = "게시글 작성자 공개 정보")
public record PostAuthorResponse(
    @Schema(description = "작성자 사용자 ID") Long userId,
    @Schema(description = "작성자 닉네임") String nickname) {}
