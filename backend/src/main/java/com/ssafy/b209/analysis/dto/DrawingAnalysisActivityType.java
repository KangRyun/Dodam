package com.ssafy.b209.analysis.dto;

/**
 * AI 그림 분석 모델을 선택하는 출시 대상 활동 유형이다.
 *
 * <p>일반 그림 유형의 DB 코드를 그대로 무제한 전달하지 않고, AI와 합의된 활동만 내부 계약에 노출한다.
 */
public enum DrawingAnalysisActivityType {
  /** HOUSE, TREE, PERSON 전용 HTP 분석이다. */
  HTP,
  /** 그림일기용 일반 스케치 분석이다. */
  ART_DIARY
}
