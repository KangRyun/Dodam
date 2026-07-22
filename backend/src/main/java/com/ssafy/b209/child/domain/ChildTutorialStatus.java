package com.ssafy.b209.child.domain;

/** 아동의 서비스 이용 안내 진행 상태를 표현한다. */
public enum ChildTutorialStatus {
  /** Tutorial을 아직 시작하지 않은 상태다. */
  NOT_STARTED,
  /** Tutorial을 진행하고 있는 상태다. */
  IN_PROGRESS,
  /** Tutorial을 정상적으로 마친 상태다. */
  COMPLETED,
  /** Tutorial을 건너뛴 상태다. */
  SKIPPED
}
