package com.ssafy.b209.community.repository;

import com.ssafy.b209.auth.domain.UserRole;
import com.ssafy.b209.community.domain.PostFeed;
import com.ssafy.b209.community.domain.PostListSort;
import com.ssafy.b209.community.domain.PostType;

/**
 * DB v1.2 게시글 목록 Native Query에 전달하는 검증 완료 검색 조건이다.
 *
 * @param postType 선택 게시글 유형 또는 전체 조회면 {@code null}
 * @param keywordPattern LIKE 특수 문자를 이스케이프한 제목·내용 검색 패턴
 * @param feed 전체 또는 팔로우 전문가 피드 범위
 * @param authorRole 작성자 역할 또는 전체 조회면 {@code null}
 * @param page 0부터 시작하는 페이지 번호
 * @param size 페이지 크기
 * @param sort 허용된 정렬 필드와 방향
 * @param viewerUserId likedByMe와 팔로우 범위 계산에 쓰는 인증 사용자 ID
 */
public record PostListSearchCriteria(
    PostType postType,
    String keywordPattern,
    PostFeed feed,
    UserRole authorRole,
    int page,
    int size,
    PostListSort sort,
    Long viewerUserId) {}
