package com.ssafy.b209.global.response;

import org.springframework.http.HttpStatus;

/** 도메인에 종속되지 않고 여러 API에서 공유하는 성공 코드를 관리한다. */
public enum CommonSuccessCode implements SuccessCode {
  /** 일반적인 조회 또는 처리 성공을 나타낸다. */
  OK(HttpStatus.OK, "COMMON_200", "요청이 성공했습니다."),

  /** 새로운 리소스가 생성된 성공을 나타낸다. */
  CREATED(HttpStatus.CREATED, "COMMON_201", "리소스가 생성되었습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommonSuccessCode(HttpStatus httpStatus, String code, String message) {
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
