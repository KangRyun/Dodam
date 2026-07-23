package com.ssafy.b209.community.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.ssafy.b209.community.domain.PostType;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * {@code GET /api/v1/posts}의 게시글 한 건 응답이다.
 *
 * @param postId 게시글 식별자
 * @param postType 게시글 유형
 * @param title 게시글 제목
 * @param previewContent 전체 본문을 제외한 목록용 미리보기
 * @param author 익명화 정책을 적용한 작성자 정보
 * @param isAnonymous 익명 게시글 여부
 * @param likeCount 현재 좋아요 집계
 * @param commentCount 공개·활성 댓글 집계
 * @param likedByMe 현재 인증 사용자의 좋아요 여부
 * @param createdAt 게시글 생성 UTC 시각
 * @param updatedAt 게시글 수정 UTC 시각
 */
@Schema(description = "커뮤니티 게시글 목록 항목")
public record PostListItemResponse(
    Long postId,
    PostType postType,
    String title,
    String previewContent,
    PostAuthorResponse author,
    @JsonProperty("isAnonymous") boolean isAnonymous,
    long likeCount,
    long commentCount,
    boolean likedByMe,
    Instant createdAt,
    Instant updatedAt) {}
