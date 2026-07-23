package com.ssafy.b209.user.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 사용자 API에서 클라이언트에 반환하는 오류 코드를 정의한다. */
public enum UserErrorCode implements ErrorCode {
  /** Onboarding에서 허용하지 않는 역할(예: {@code ADMIN})을 요청한 경우다. */
  ROLE_NOT_ALLOWED(HttpStatus.BAD_REQUEST, "USER_400_001", "선택할 수 없는 역할입니다."),

  /** 인증된 사용자 식별자에 해당하는 사용자를 찾을 수 없는 경우다. */
  USER_NOT_FOUND(HttpStatus.NOT_FOUND, "USER_404_001", "사용자 정보를 찾을 수 없습니다."),

  /** 회원 탈퇴 확인 문자열이 정확한 값과 일치하지 않는 경우다. */
  WITHDRAWAL_CONFIRMATION_MISMATCH(
      HttpStatus.BAD_REQUEST, "USER_400_002", "회원 탈퇴 확인 값이 올바르지 않습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  UserErrorCode(HttpStatus httpStatus, String code, String message) {
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
