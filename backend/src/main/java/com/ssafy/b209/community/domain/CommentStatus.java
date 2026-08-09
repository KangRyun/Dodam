package com.ssafy.b209.community.domain;

/** 커뮤니티 댓글의 공개 및 삭제 상태다. */
public enum CommentStatus {
  /** 일반 사용자에게 공개되는 상태다. */
  ACTIVE,
  /** 운영 정책에 따라 숨김 처리된 상태다. */
  HIDDEN,
  /** Soft Delete가 완료된 상태다. */
  DELETED
}
