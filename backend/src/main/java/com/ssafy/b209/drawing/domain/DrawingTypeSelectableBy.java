package com.ssafy.b209.drawing.domain;

/** 그림 활동 유형을 선택할 수 있는 주체를 표현한다. */
public enum DrawingTypeSelectableBy {
  /** 보호자만 선택할 수 있는 유형이다. */
  GUARDIAN,
  /** 아동만 선택할 수 있는 유형이다. */
  CHILD,
  /** 보호자와 아동 모두 선택할 수 있는 유형이다. */
  BOTH
}
