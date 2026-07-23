package com.ssafy.b209.analysis.dto;

/** 공개 API에서 허용하는 그림 분석 재시도 사유를 정의한다. */
public enum DrawingAnalysisRetryReason {
  /** 보호자가 실패 결과 화면에서 재시도를 명시적으로 요청한 경우다. */
  USER_REQUEST
}
