package com.ssafy.b209.report.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** REPORT-02 보호자용 리포트 상세 조회가 공개하는 안전한 오류 코드다. */
public enum ReportDetailErrorCode implements ErrorCode {
  /** 리포트가 없거나 숨김 처리돼 보호자에게 노출하지 않는 경우다. */
  REPORT_NOT_FOUND(HttpStatus.NOT_FOUND, "REPORT_NOT_FOUND", "리포트를 찾을 수 없습니다."),

  /** 리포트가 연결된 아동과 보호자 사이에 접근 권한이 없는 경우다. */
  REPORT_ACCESS_DENIED(HttpStatus.FORBIDDEN, "REPORT_ACCESS_DENIED", "리포트에 접근할 권한이 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ReportDetailErrorCode(HttpStatus httpStatus, String code, String message) {
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
