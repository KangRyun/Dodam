package com.ssafy.b209.community.dto;

import com.ssafy.b209.auth.domain.UserRole;
import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 비익명 댓글에 공개하는 작성자 정보다.
 *
 * @param userId 작성자 사용자 ID
 * @param nickname 표시 이름
 * @param role 사용자 역할
 * @param profileImageUrl 프로필 이미지 URL
 */
@Schema(description = "댓글 작성자 공개 정보")
public record CommentAuthorResponse(
    Long userId, String nickname, UserRole role, String profileImageUrl) {}
