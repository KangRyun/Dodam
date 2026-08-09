package com.ssafy.b209.community.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 게시글 좋아요 등록 결과다.
 *
 * @param postId 좋아요 대상 게시글 ID
 * @param liked 요청 처리 후 현재 사용자의 좋아요 여부
 * @param likeCount 요청 처리 후 게시글 전체 좋아요 수
 */
@Schema(description = "커뮤니티 게시글 좋아요 등록 결과")
public record PostLikeResponse(Long postId, boolean liked, long likeCount) {}
