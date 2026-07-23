package com.ssafy.b209.child.domain;

/**
 * 아동이 대화에서 사용할 수 있는 응답 방식이다.
 *
 * <p>{@code child_response_modes.response_mode} 컬럼 제약과 일치하며 대화 도메인의 응답 방식과는 별개의 값 집합이다.
 */
public enum ResponseMode {
  /** 음성으로 응답한다. */
  VOICE,
  /** 이모지로 응답한다. */
  EMOJI,
  /** 색상으로 응답한다. */
  COLOR,
  /** 그림으로 응답한다. */
  PICTURE,
  /** 텍스트로 응답한다. */
  TEXT
}
