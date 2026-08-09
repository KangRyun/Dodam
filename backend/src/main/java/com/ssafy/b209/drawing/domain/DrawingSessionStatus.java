package com.ssafy.b209.drawing.domain;

/** 그림 활동 세션의 처리 상태를 표현한다. */
public enum DrawingSessionStatus {
  /** 그림 활동이 진행 중인 상태다. */
  IN_PROGRESS,
  /** 그림 활동의 전체 절차를 마친 상태다. */
  COMPLETED,
  /** 처리 오류로 그림 활동을 완료하지 못한 상태다. */
  FAILED,
  /** 새 활동 시작으로 재개가 종료됐지만 운영 기록과 원본 자료는 보존하는 상태다. */
  ABANDONED,
  /** 그림 활동이 삭제 처리된 상태다. */
  DELETED
}
