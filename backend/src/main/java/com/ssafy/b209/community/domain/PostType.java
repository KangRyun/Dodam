package com.ssafy.b209.community.domain;

/** DB v1.2 {@code community_posts.post_type}에 저장되는 게시글 유형이다. */
public enum PostType {
  /** 보호자의 경험 공유 글이다. */
  GUARDIAN_STORY,
  /** 미술 활동 후기 글이다. */
  ACTIVITY_REVIEW,
  /** 전문가 칼럼이다. */
  EXPERT_COLUMN,
  /** 미술 자료 글이다. */
  ART_RESOURCE,
  /** 그림 활동 안내 글이다. */
  DRAWING_GUIDE,
  /** 전문가 질의응답 글이다. */
  EXPERT_QNA,
  /** 운영 공지 글이다. */
  NOTICE
}
