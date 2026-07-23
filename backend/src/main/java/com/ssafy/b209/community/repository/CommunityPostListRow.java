package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.PostType;
import java.time.LocalDateTime;

/**
 * DB Native Query가 반환한 게시글 목록 한 행의 안전한 조회 전용 Snapshot이다.
 *
 * @param postId 게시글 식별자
 * @param postType DB 게시글 유형
 * @param title 게시글 제목
 * @param content 게시글 원문. Service가 preview로 축약한다
 * @param anonymous DB 익명 여부
 * @param createdAt 생성 시각
 * @param updatedAt 수정 시각
 * @param authorId 작성자 사용자 ID
 * @param nickname 사용자 닉네임
 * @param likeCount 좋아요 관계 행 집계
 * @param commentCount 공개·활성 댓글 관계 행 집계
 * @param likedByMe 현재 사용자 좋아요 관계 존재 여부
 */
public record CommunityPostListRow(
    Long postId,
    PostType postType,
    String title,
    String content,
    boolean anonymous,
    LocalDateTime createdAt,
    LocalDateTime updatedAt,
    Long authorId,
    String nickname,
    long likeCount,
    long commentCount,
    boolean likedByMe) {}
