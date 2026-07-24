package com.ssafy.b209.community.domain;

/** DB v1.2 {@code community_posts.post_status}에 저장되는 게시글 노출 상태다. */
public enum PostStatus {
  /** 일반 공개 대상인 활성 게시글이다. */
  ACTIVE,
  /** 운영 정책으로 숨겨진 게시글이다. */
  HIDDEN,
  /** 삭제 처리된 게시글이다. */
  DELETED
}
