package com.ssafy.b209.community.repository;

import com.ssafy.b209.community.domain.PostType;
import java.time.LocalDateTime;

/**
 * 공개 조건을 만족한 게시글 상세 Native Query의 한 행이다.
 *
 * @param postId 게시글 식별자
 * @param postType DB 게시글 유형
 * @param title 게시글 제목
 * @param content 게시글 원문
 * @param anonymous DB 익명 여부
 * @param createdAt 생성 시각
 * @param updatedAt 수정 시각
 * @param authorId 작성자 사용자 ID
 * @param nickname 작성자 닉네임
 * @param profileImageUrl 작성자 프로필 이미지 URL
 * @param likeCount 좋아요 관계 행 집계
 * @param commentCount 공개·활성 댓글 관계 행 집계
 * @param likedByMe 현재 사용자 좋아요 관계 존재 여부
 * @param editableByMe 현재 사용자가 수정 가능한지 계산한 값
 */
public record CommunityPostDetailRow(
    Long postId,
    PostType postType,
    String title,
    String content,
    boolean anonymous,
    LocalDateTime createdAt,
    LocalDateTime updatedAt,
    Long authorId,
    String nickname,
    String profileImageUrl,
    long likeCount,
    long commentCount,
    boolean likedByMe,
    boolean editableByMe) {}
