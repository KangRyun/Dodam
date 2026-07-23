package com.ssafy.b209.community.domain;

/** 게시글 목록에서 선택할 전체 또는 보호자 팔로우 피드 범위다. */
public enum PostFeed {
  /** 공개된 모든 활성 게시글을 조회한다. */
  ALL,
  /** 로그인한 보호자가 팔로우한 전문가의 게시글만 조회한다. */
  FOLLOWING
}
