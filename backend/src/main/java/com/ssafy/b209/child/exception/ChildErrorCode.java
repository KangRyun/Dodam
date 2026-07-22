package com.ssafy.b209.child.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 아동 프로필 API에서 클라이언트에 반환하는 오류 코드를 정의한다. */
public enum ChildErrorCode implements ErrorCode {
  /** 아동이 없거나 삭제됐거나 요청 보호자에게 연결되지 않은 경우다. */
  CHILD_NOT_FOUND(HttpStatus.NOT_FOUND, "CHILD_404_001", "아동 정보를 찾을 수 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ChildErrorCode(HttpStatus httpStatus, String code, String message) {
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
