package com.ssafy.b209.analysis.dto;

/** AI 서버에 요청할 그림 분석 작업의 종류를 나타낸다. 외부 분석 API의 분석 시점 유형과는 별개의 계약이다. */
public enum DrawingAnalysisType {
  /** 그림에서 객체와 위치를 탐지한다. */
  OBJECT_DETECTION
}
