package com.ssafy.b209.drawing.domain;

/** 그림 활동에 그림을 제공하는 방식을 표현한다. */
public enum DrawingInputMethod {
  /** 서비스 Canvas에서 직접 그림을 그리는 방식이다. */
  CANVAS,
  /** 별도 업로드 절차로 준비한 그림을 사용하는 방식이다. */
  UPLOAD
}
