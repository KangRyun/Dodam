package com.ssafy.b209.report.domain;

/** 리포트 생성과 공개 생명주기를 나타낸다. */
public enum ReportStatus {
  /** 리포트 상세 내용을 생성하는 중이다. */
  GENERATING,
  /** 리포트 생성이 완료됐다. */
  COMPLETED,
  /** 리포트 생성에 실패했다. */
  FAILED,
  /** 보호자 화면에서 숨김 처리됐다. */
  HIDDEN
}
