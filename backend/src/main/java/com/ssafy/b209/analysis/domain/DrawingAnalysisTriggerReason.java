package com.ssafy.b209.analysis.domain;

/** 분석 실행이 시작된 실제 계기를 저장하고 AI 내부 계약에 전달할 때 사용하는 유형이다. */
public enum DrawingAnalysisTriggerReason {
  /** 마지막 그림 입력 후 일정 시간 동안 추가 입력이 없어 실행한다. */
  PAUSE,
  /** 일정 시간 간격으로 실행한다. */
  INTERVAL,
  /** 누적 Stroke 수를 기준으로 실행한다. */
  STROKE_COUNT,
  /** 직전 그림과의 변화율을 기준으로 실행한다. */
  CHANGE_RATIO,
  /** 사용자 또는 기존 Client가 명시적으로 요청한다. */
  USER_REQUEST,
  /** 최종 그림 저장 완료를 계기로 실행한다. */
  DRAWING_COMPLETE,
  /** 활동 전체 완료를 계기로 실행한다. */
  ACTIVITY_COMPLETE,
  /** 실패한 분석을 다시 실행한다. */
  RETRY
}
