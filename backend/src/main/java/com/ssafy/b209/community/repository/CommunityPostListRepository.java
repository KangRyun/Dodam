package com.ssafy.b209.community.repository;

/**
 * DB v1.2의 게시글·작성자·좋아요·댓글·전문가 팔로우 관계를 사용해 공개 게시글 목록을 조회한다.
 *
 * <p>목록 응답의 집계 값과 현재 사용자 좋아요 여부는 모두 조회 시점의 관계 테이블로 계산한다. 별도 count 컬럼이나 JSON Snapshot은 사용하지 않는다.
 */
public interface CommunityPostListRepository {

  /**
   * 공개·활성·미삭제 게시글을 조건과 페이지에 맞춰 조회한다.
   *
   * @param criteria Service에서 검증한 필터, 정렬, 페이지와 현재 사용자 ID
   * @return 목록 행과 전체 건수
   */
  CommunityPostListPage findPosts(PostListSearchCriteria criteria);
}
