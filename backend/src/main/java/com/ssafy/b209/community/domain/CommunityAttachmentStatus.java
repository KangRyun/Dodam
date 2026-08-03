package com.ssafy.b209.community.domain;

/** 사전 업로드된 커뮤니티 첨부 이미지의 연결 상태다. */
public enum CommunityAttachmentStatus {
  /** 게시글 연결 전이며 만료 정책이 적용되는 상태다. */
  TEMP,
  /** 게시글에 연결되어 공개 게시글 수명주기를 따르는 상태다. */
  ATTACHED
}
