package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 댓글 작성·수정 결과다.
 *
 * @param commentId 댓글 ID
 * @param postId 소속 게시글 ID
 * @param author 비익명 작성자 정보
 * @param anonymous 익명 여부
 * @param content 댓글 본문
 * @param expertAnswer 전문가 답변 여부
 * @param accepted 채택 여부
 * @param editableByMe 현재 사용자의 수정·삭제 가능 여부
 * @param createdAt 생성 UTC 시각
 * @param updatedAt 수정 UTC 시각
 */
@Schema(description = "커뮤니티 댓글")
public record CommentResponse(
    Long commentId,
    Long postId,
    CommentAuthorResponse author,
    boolean anonymous,
    String content,
    boolean expertAnswer,
    boolean accepted,
    boolean editableByMe,
    Instant createdAt,
    Instant updatedAt) {}
