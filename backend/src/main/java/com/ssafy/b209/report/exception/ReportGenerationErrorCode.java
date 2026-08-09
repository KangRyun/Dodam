package com.ssafy.b209.report.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 관찰 리포트 재생성 요청의 입력·상태·동시성 오류를 정의한다. */
public enum ReportGenerationErrorCode implements ErrorCode {
  /** Idempotency-Key Header가 누락된 경우다. */
  IDEMPOTENCY_KEY_REQUIRED(HttpStatus.BAD_REQUEST, "REPORT_400_001", "Idempotency-Key가 필요합니다."),
  /** Idempotency-Key가 허용 길이 또는 문자 규칙을 위반한 경우다. */
  IDEMPOTENCY_KEY_INVALID(
      HttpStatus.BAD_REQUEST, "REPORT_400_002", "Idempotency-Key 형식이 올바르지 않습니다."),
  /** 같은 Idempotency-Key가 다른 재생성 요청에 사용된 경우다. */
  IDEMPOTENCY_KEY_CONFLICT(
      HttpStatus.CONFLICT, "REPORT_409_002", "동일한 Idempotency-Key가 다른 요청에 사용됐습니다."),
  /** 최신 FAILED 리포트가 아니어서 재생성을 허용할 수 없는 경우다. */
  REGENERATION_NOT_ALLOWED(HttpStatus.CONFLICT, "REPORT_409_003", "최신 실패 리포트만 재생성할 수 있습니다."),
  /** 재생성에 사용할 FINAL Asset을 찾을 수 없는 경우다. */
  FINAL_ASSET_REQUIRED(HttpStatus.CONFLICT, "REPORT_409_004", "리포트 재생성에 사용할 최종 그림이 필요합니다."),
  /** 동시에 처리된 요청 또는 DB 제약으로 재생성 접수가 충돌한 경우다. */
  REGENERATION_CONFLICT(HttpStatus.CONFLICT, "REPORT_409_005", "리포트 재생성 요청이 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ReportGenerationErrorCode(HttpStatus httpStatus, String code, String message) {
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
