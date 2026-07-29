package com.ssafy.b209.report.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 보호자용 관찰 리포트 PDF 내보내기에서 사용하는 오류 코드다. */
public enum ReportExportErrorCode implements ErrorCode {
  /** Idempotency-Key Header가 누락된 경우다. */
  IDEMPOTENCY_KEY_REQUIRED(
      HttpStatus.BAD_REQUEST, "REPORT_EXPORT_400_001", "Idempotency-Key가 필요합니다."),
  /** Idempotency-Key가 허용 길이 또는 문자 규칙을 위반한 경우다. */
  IDEMPOTENCY_KEY_INVALID(
      HttpStatus.BAD_REQUEST, "REPORT_EXPORT_400_002", "Idempotency-Key 형식이 올바르지 않습니다."),
  /** 아직 완료되지 않은 리포트를 내보내려는 경우다. */
  REPORT_EXPORT_NOT_READY(HttpStatus.CONFLICT, "REPORT_EXPORT_409_001", "완료된 리포트만 다운로드할 수 있습니다."),
  /** 요청한 내보내기 결과가 원본 리포트와 일치하지 않는 경우다. */
  REPORT_EXPORT_NOT_FOUND(HttpStatus.NOT_FOUND, "REPORT_EXPORT_404_001", "리포트 내보내기 결과를 찾을 수 없습니다."),
  /** 안전한 PDF 문서를 생성하지 못한 경우다. */
  REPORT_EXPORT_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "REPORT_EXPORT_500_001", "리포트 PDF 생성에 실패했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ReportExportErrorCode(HttpStatus httpStatus, String code, String message) {
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
