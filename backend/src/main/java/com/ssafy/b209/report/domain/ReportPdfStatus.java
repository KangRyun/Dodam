package com.ssafy.b209.report.domain;

/** 리포트 PDF 생성 상태를 나타낸다. */
public enum ReportPdfStatus {
  /** PDF 생성이 요청되지 않았다. */
  NONE,
  /** PDF를 생성하는 중이다. */
  GENERATING,
  /** PDF 파일을 사용할 수 있다. */
  READY,
  /** PDF 생성에 실패했다. */
  FAILED
}
