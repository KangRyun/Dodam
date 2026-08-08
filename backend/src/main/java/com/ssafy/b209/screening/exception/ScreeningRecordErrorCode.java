package com.ssafy.b209.screening.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 보호자가 옮겨 적는 선별 결과 기록이 공개하는 안전한 오류 코드다. */
public enum ScreeningRecordErrorCode implements ErrorCode {
  /** 보호자와 아동의 연결이 없거나 아동이 활성 상태가 아닌 경우다. */
  SCREENING_ACCESS_DENIED(
      HttpStatus.FORBIDDEN, "SCREENING_ACCESS_DENIED", "아이의 검사 기록에 접근할 권한이 없습니다."),

  /** 등록부 allow-list에 없는 도구 식별자를 보낸 경우다. 임의의 검사명이 아동 기록에 남지 않게 막는다. */
  SCREENING_INSTRUMENT_NOT_ALLOWED(
      HttpStatus.BAD_REQUEST, "SCREENING_INSTRUMENT_NOT_ALLOWED", "등록되지 않은 검사 도구입니다."),

  /** 임상 기록 보관 동의 이력이 확인되지 않은 경우다. */
  SCREENING_CONSENT_REQUIRED(
      HttpStatus.FORBIDDEN, "SCREENING_CONSENT_REQUIRED", "아이의 검사 기록을 보관하려면 별도 동의가 필요합니다."),

  /** 이미 삭제됐거나 다른 아이의 기록을 가리킨 경우다. */
  SCREENING_RECORD_NOT_FOUND(
      HttpStatus.NOT_FOUND, "SCREENING_RECORD_NOT_FOUND", "검사 기록을 찾을 수 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ScreeningRecordErrorCode(HttpStatus httpStatus, String code, String message) {
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
