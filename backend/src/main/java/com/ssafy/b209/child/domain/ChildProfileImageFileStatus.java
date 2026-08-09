package com.ssafy.b209.child.domain;

/** 아동 프로필 이미지 파일이 임시 업로드 상태인지 프로필에 연결된 상태인지 구분한다. */
public enum ChildProfileImageFileStatus {
  /** 아동과 연결되기 전이며 만료 후 정리할 수 있는 파일이다. */
  TEMP,
  /** 특정 아동 프로필에 연결되어 조회에 사용되는 파일이다. */
  ATTACHED
}
