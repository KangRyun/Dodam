package com.ssafy.b209.community.dto;

import com.ssafy.b209.community.domain.PostType;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * {@code PATCH /api/v1/posts/{postId}}의 커뮤니티 게시글 수정 요청 본문이다.
 *
 * <p>명세 16.3의 작성·수정 공유 스키마에 따라 전체 교체 성격의 값을 받는다. {@code templateData}와 {@code attachments}는 작성과
 * 동일하게 이번 범위에서 형식만 수용하고 저장하지 않는다.
 *
 * @param postType 교체할 게시글 유형
 * @param title 게시글 제목, 1~200자
 * @param content 게시글 본문, 1~20,000자
 * @param anonymous 익명 게시글 여부, 미지정 시 {@code false}
 * @param templateData 유형별 Template 입력값, 이번 범위에서는 저장하지 않음
 * @param attachments 첨부 후보 목록, 최대 5개까지 형식만 검증하고 저장하지 않음
 */
@Schema(description = "커뮤니티 게시글 수정 요청")
public record UpdatePostRequest(
    @Schema(description = "게시글 유형") @NotNull PostType postType,
    @Schema(description = "게시글 제목") @NotBlank @Size(max = 200) String title,
    @Schema(description = "게시글 본문") @NotBlank @Size(max = 20000) String content,
    @Schema(description = "익명 게시글 여부") boolean anonymous,
    @Schema(description = "유형별 Template 입력값") Object templateData,
    @Schema(description = "첨부 후보 목록") @Size(max = 5) List<Object> attachments) {}
