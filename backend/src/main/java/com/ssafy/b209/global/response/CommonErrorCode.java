package com.ssafy.b209.global.response;

import org.springframework.http.HttpStatus;

/** 도메인에 종속되지 않고 여러 API에서 공유하는 오류 코드를 관리한다. */
public enum CommonErrorCode implements ErrorCode {
  /** 요청 값 또는 Validation이 올바르지 않은 경우다. */
  INVALID_INPUT_VALUE(HttpStatus.BAD_REQUEST, "COMMON_400_001", "요청 값이 올바르지 않습니다."),

  /** 요청 값의 타입 변환에 실패한 경우다. */
  INVALID_TYPE_VALUE(HttpStatus.BAD_REQUEST, "COMMON_400_002", "요청 값의 형식이 올바르지 않습니다."),

  /** 요청 본문을 읽거나 역직렬화할 수 없는 경우다. */
  MESSAGE_NOT_READABLE(HttpStatus.BAD_REQUEST, "COMMON_400_003", "요청 본문을 읽을 수 없습니다."),

  /** 필수 요청 파라미터가 누락된 경우다. */
  MISSING_REQUEST_PARAMETER(HttpStatus.BAD_REQUEST, "COMMON_400_004", "필수 요청 파라미터가 누락되었습니다."),

  /** 요청한 API 또는 리소스를 찾을 수 없는 경우다. */
  RESOURCE_NOT_FOUND(HttpStatus.NOT_FOUND, "COMMON_404_001", "요청한 리소스를 찾을 수 없습니다."),

  /** 요청한 HTTP Method를 지원하지 않는 경우다. */
  METHOD_NOT_ALLOWED(HttpStatus.METHOD_NOT_ALLOWED, "COMMON_405_001", "지원하지 않는 HTTP 메서드입니다."),

  /** 요청이 데이터 무결성 조건과 충돌한 경우다. */
  DATA_INTEGRITY_VIOLATION(HttpStatus.CONFLICT, "COMMON_409_001", "요청이 현재 데이터 상태와 충돌합니다."),

  /** 예상하지 못한 서버 내부 오류가 발생한 경우다. */
  INTERNAL_SERVER_ERROR(HttpStatus.INTERNAL_SERVER_ERROR, "COMMON_500_001", "서버 내부 오류가 발생했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommonErrorCode(HttpStatus httpStatus, String code, String message) {
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
