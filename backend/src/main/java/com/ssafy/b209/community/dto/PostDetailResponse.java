package com.ssafy.b209.community.dto;

import com.ssafy.b209.community.domain.PostType;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;

/**
 * {@code GET /api/v1/posts/{postId}}의 공개 게시글 상세 응답이다.
 *
 * @param postId 게시글 식별자
 * @param postType 게시글 유형
 * @param title 게시글 제목
 * @param content 공개 가능한 전체 본문
 * @param author 비익명 글의 작성자 공개 정보, 익명 또는 삭제 작성자면 {@code null}
 * @param anonymous 익명 게시글 여부
 * @param attachments 노출 순서대로 정렬된 첨부 이미지 목록
 * @param templateData display_order 순서를 유지한 Template 데이터
 * @param likeCount 현재 좋아요 집계
 * @param commentCount 공개·활성 댓글 집계
 * @param likedByMe 현재 인증 사용자의 좋아요 여부
 * @param editableByMe 현재 인증 사용자의 수정 가능 여부
 * @param createdAt 게시글 생성 UTC 시각
 * @param updatedAt 게시글 수정 UTC 시각
 */
@Schema(description = "커뮤니티 게시글 상세")
public record PostDetailResponse(
    Long postId,
    PostType postType,
    String title,
    String content,
    PostDetailAuthorResponse author,
    boolean anonymous,
    List<CommunityAttachmentResponse> attachments,
    List<PostTemplateDataResponse> templateData,
    long likeCount,
    long commentCount,
    boolean likedByMe,
    boolean editableByMe,
    Instant createdAt,
    Instant updatedAt) {}
