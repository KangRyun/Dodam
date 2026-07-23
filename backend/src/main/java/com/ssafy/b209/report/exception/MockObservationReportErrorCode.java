package com.ssafy.b209.report.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 관찰 리포트 생성 과정에서 외부에 반환할 안전한 오류 코드를 정의한다. */
public enum MockObservationReportErrorCode implements ErrorCode {
  /** 생성 대상 최종 분석을 찾을 수 없는 경우다. */
  ANALYSIS_NOT_FOUND(HttpStatus.NOT_FOUND, "REPORT_404_001", "리포트 생성 대상 분석을 찾을 수 없습니다."),
  /** 분석에 연결된 리포트를 찾을 수 없는 경우다. */
  REPORT_NOT_FOUND(HttpStatus.NOT_FOUND, "REPORT_404_002", "리포트를 찾을 수 없습니다."),
  /** 관찰 리포트 생성 결과가 합의한 계약과 일치하지 않는 경우다. */
  OBSERVATION_INVALID_RESPONSE(
      HttpStatus.BAD_GATEWAY, "REPORT_502_001", "관찰 리포트 생성 결과를 처리할 수 없습니다."),
  /** 관찰 리포트 생성 요청을 완료하지 못한 경우다. */
  OBSERVATION_GENERATION_FAILED(HttpStatus.BAD_GATEWAY, "REPORT_502_002", "관찰 리포트 생성을 완료하지 못했습니다."),
  /** 유효한 관찰 리포트를 데이터베이스에 저장하지 못한 경우다. */
  REPORT_STORAGE_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "REPORT_500_001", "리포트 저장 중 오류가 발생했습니다."),
  /** 저장 과정에서 유일성 제약 충돌이 발생한 경우다. */
  REPORT_STORAGE_CONFLICT(HttpStatus.CONFLICT, "REPORT_409_001", "리포트 저장 중 충돌이 발생했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  MockObservationReportErrorCode(HttpStatus httpStatus, String code, String message) {
    this.httpStatus = httpStatus;
    this.code = code;
    this.message = message;
  }

  @Override
  public HttpStatus getHttpStatus() {
    return httpStatus;
  }

  @Override
  public String getCode() {
    return code;
  }

  @Override
  public String getMessage() {
    return message;
  }
}
