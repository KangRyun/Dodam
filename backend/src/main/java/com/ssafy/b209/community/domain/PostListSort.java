package com.ssafy.b209.community.domain;

/**
 * 게시글 목록에서 허용하는 정렬 필드와 방향 조합이다.
 *
 * @param field 정렬 기준 필드
 * @param direction 정렬 방향
 */
public record PostListSort(SortField field, SortDirection direction) {

  /** 목록 API에서 허용하는 정렬 필드다. */
  public enum SortField {
    /** 게시글 생성 시각을 기준으로 정렬한다. */
    CREATED_AT,
    /** 게시글 좋아요 수를 기준으로 정렬한다. */
    LIKE_COUNT
  }

  /** 목록 API에서 허용하는 정렬 방향이다. */
  public enum SortDirection {
    /** 오름차순 정렬이다. */
    ASC,
    /** 내림차순 정렬이다. */
    DESC
  }
}
