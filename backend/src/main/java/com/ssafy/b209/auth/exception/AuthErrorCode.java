package com.ssafy.b209.auth.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** OAuth 인증 계정 처리 과정에서 클라이언트에 안전하게 공개할 오류를 정의한다. */
public enum AuthErrorCode implements ErrorCode {
  /** 동시에 동일한 OAuth 계정 연결이 생성되어 단일 사용자로 확정할 수 없는 경우이다. */
  ACCOUNT_LINK_CONFLICT(HttpStatus.CONFLICT, "AUTH_409_001", "이미 연결 처리 중이거나 연결된 OAuth 계정입니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  AuthErrorCode(HttpStatus httpStatus, String code, String message) {
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
