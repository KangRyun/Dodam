package com.ssafy.b209.screening.domain;

/** 결과에 따른 다음 걸음이다. 결과 자체가 아니라 무엇을 하면 되는지를 담는다. */
public enum ScreeningFollowupLevel {
  /** 특별한 후속 조치가 적혀 있지 않다. */
  NONE,

  /** 보호자와 상의해 볼 것을 권한다. */
  DISCUSS_WITH_GUARDIAN,

  /** 추가 평가 일정을 잡을 것을 권한다. */
  SCHEDULE_FURTHER_EVALUATION
}
