package com.ssafy.b209.analysis.dto;

/** Spring Boot와 AI 서버 사이에서 교환하는 그림 분석 작업의 진행 상태를 나타낸다. */
public enum DrawingAnalysisStatus {
  /** 분석 요청이 대기 중인 상태다. */
  PENDING,
  /** AI 서버가 분석을 수행 중인 상태다. */
  PROCESSING,
  /** 분석이 정상적으로 완료된 상태다. */
  SUCCEEDED,
  /** 분석을 완료하지 못한 상태다. */
  FAILED
}
