package com.ssafy.b209.auth.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** OAuth 인증 계정 처리 과정에서 클라이언트에 안전하게 공개할 오류를 정의한다. */
public enum AuthErrorCode implements ErrorCode {
  /** 동시에 동일한 OAuth 계정 연결이 생성되어 단일 사용자로 확정할 수 없는 경우이다. */
  ACCOUNT_LINK_CONFLICT(HttpStatus.CONFLICT, "AUTH_409_001", "이미 연결 처리 중이거나 연결된 OAuth 계정입니다."),

  /** authorization code가 만료되었거나 Provider가 거부한 경우이다. */
  OAUTH_CODE_INVALID(HttpStatus.UNAUTHORIZED, "AUTH_401_001", "OAuth 인증 정보가 유효하지 않습니다."),

  /** 정지되었거나 과거 탈퇴 상태인 사용자가 로그인을 시도한 경우이다. */
  ACCOUNT_SUSPENDED(HttpStatus.FORBIDDEN, "AUTH_403_001", "이용이 제한된 계정입니다."),

  /** 요청한 Provider 또는 Redirect URI 설정이 허용되지 않은 경우이다. */
  OAUTH_REQUEST_INVALID(HttpStatus.BAD_REQUEST, "AUTH_400_001", "OAuth 로그인 요청이 유효하지 않습니다."),

  /** Provider가 정상 응답하지 않거나 검증 가능한 신원을 제공하지 않은 경우이다. */
  OAUTH_PROVIDER_ERROR(HttpStatus.BAD_GATEWAY, "AUTH_502_001", "OAuth Provider와 통신하지 못했습니다."),

  /** 운영 환경의 OAuth 또는 JWT 필수 설정이 누락되거나 안전하지 않은 경우이다. */
  AUTH_CONFIGURATION_INVALID(
      HttpStatus.SERVICE_UNAVAILABLE, "AUTH_503_001", "인증 서비스 설정이 완료되지 않았습니다."),

  /** 인증 계정이 참조하는 사용자를 찾을 수 없어 로그인을 완료할 수 없는 경우이다. */
  AUTH_ACCOUNT_INVALID(HttpStatus.INTERNAL_SERVER_ERROR, "AUTH_500_001", "인증 계정 정보를 확인하지 못했습니다.");

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
