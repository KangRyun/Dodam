package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 댓글 작성 요청이다.
 *
 * @param content 댓글 본문
 * @param anonymous 익명 표시 여부
 */
@Schema(description = "커뮤니티 댓글 작성 요청")
public record CreateCommentRequest(@NotBlank @Size(max = 5000) String content, boolean anonymous) {}
