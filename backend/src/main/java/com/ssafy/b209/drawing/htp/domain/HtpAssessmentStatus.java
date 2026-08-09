package com.ssafy.b209.drawing.htp.domain;

/** 집·나무·사람 세 그림으로 구성된 HTP 활동 묶음의 처리 상태다. */
public enum HtpAssessmentStatus {
  /** 하나 이상의 그림 단계가 진행 중인 상태다. */
  IN_PROGRESS,
  /** 세 단계 결과를 종합 분석하는 상태다. */
  ANALYZING,
  /** 종합 분석과 활동 완료 처리가 끝난 상태다. */
  COMPLETED,
  /** 종합 리포트 생성에 실패해 보호자가 다시 요청할 수 있는 상태다. */
  FAILED,
  /** 보호자가 진행 중인 HTP 활동을 포기한 상태다. */
  ABANDONED,
  /** 생성 후 24시간이 지나 더 이상 재개할 수 없는 상태다. */
  EXPIRED
}
