package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 댓글 본문 수정 요청이다.
 *
 * @param content 교체할 댓글 본문
 */
@Schema(description = "커뮤니티 댓글 수정 요청")
public record UpdateCommentRequest(@NotBlank @Size(max = 5000) String content) {}
