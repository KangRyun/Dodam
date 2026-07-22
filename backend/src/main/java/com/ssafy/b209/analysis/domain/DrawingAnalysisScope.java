package com.ssafy.b209.analysis.domain;

/** 기존 ERD의 {@code analyses.analysis_type}에 저장되는 그림 분석 시점을 나타낸다. */
public enum DrawingAnalysisScope {
  /** 그림 활동 도중 저장된 중간 스냅샷 분석이다. */
  INTERMEDIATE,
  /** 그림 활동의 최종 스냅샷 분석이다. */
  FINAL
}
