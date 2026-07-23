package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 비익명 게시글 상세에만 포함하는 작성자 공개 정보다.
 *
 * @param userId 공개 가능한 작성자 사용자 ID
 * @param nickname 공개 가능한 작성자 닉네임
 * @param profileImageUrl 공개 가능한 작성자 프로필 이미지 URL
 */
@Schema(description = "게시글 상세 작성자 공개 정보")
public record PostDetailAuthorResponse(
    @Schema(description = "작성자 사용자 ID") Long userId,
    @Schema(description = "작성자 닉네임") String nickname,
    @Schema(description = "작성자 프로필 이미지 URL") String profileImageUrl) {}
