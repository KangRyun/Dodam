package com.ssafy.b209.analysis.domain;

/** 기존 ERD의 {@code analyses.analysis_status}에 저장되는 분석 처리 상태를 나타낸다. */
public enum DrawingAnalysisState {
  /** 실행 대기 중인 분석이다. */
  PENDING,
  /** AI Client가 처리 중인 분석이다. */
  PROCESSING,
  /** 일부 분석 단계만 성공한 기존 상태다. */
  PARTIAL_SUCCESS,
  /** 분석 결과 저장까지 완료된 상태다. 기존 세션 하위 API에서만 {@code SUCCEEDED}로 변환한다. */
  SUCCESS,
  /** Client 호출 또는 결과 저장을 완료하지 못한 상태다. */
  FAILED
}
