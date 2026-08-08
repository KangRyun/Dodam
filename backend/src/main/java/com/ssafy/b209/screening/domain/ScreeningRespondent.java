package com.ssafy.b209.screening.domain;

/** 선별 결과를 보고한 사람이다. 공식 양식이 응답자를 규정하므로 함께 남긴다. */
public enum ScreeningRespondent {
  /** 보호자 보고. */
  GUARDIAN,

  /** 교사 보고. */
  TEACHER,

  /** 아이 자기보고이며 공식 양식이 허용하는 연령에서만 쓴다. */
  CHILD
}
