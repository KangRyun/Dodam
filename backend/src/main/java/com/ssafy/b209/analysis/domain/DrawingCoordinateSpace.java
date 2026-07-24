package com.ssafy.b209.analysis.domain;

/**
 * 객체 탐지 Bounding Box가 사용하는 좌표계를 구분한다.
 *
 * <p>기존 분석 결과의 픽셀 좌표와 종합 AI 분석 계약의 0~1 정규화 좌표를 같은 테이블에서 안전하게 보존하기 위해 사용한다.
 */
public enum DrawingCoordinateSpace {
  /** 원본 이미지의 픽셀을 기준으로 한 좌표다. */
  PIXEL,
  /** 이미지 너비와 높이에 대해 0~1로 정규화한 좌표다. */
  NORMALIZED
}
