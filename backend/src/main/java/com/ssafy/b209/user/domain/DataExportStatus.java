package com.ssafy.b209.user.domain;

/** 데이터 내보내기 작업의 DB 및 공개 API 상태값이다. */
public enum DataExportStatus {
  PENDING,
  PROCESSING,
  COMPLETED,
  FAILED,
  EXPIRED
}
