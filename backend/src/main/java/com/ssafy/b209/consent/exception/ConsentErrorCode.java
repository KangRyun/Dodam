package com.ssafy.b209.consent.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 동의 등록 규칙 위반을 공통 오류 응답으로 제공한다. */
public enum ConsentErrorCode implements ErrorCode {
  /** 요청한 약관 식별자가 존재하지 않는 경우이다. */
  TERM_NOT_FOUND(HttpStatus.NOT_FOUND, "CONSENT_404_001", "동의 약관을 찾을 수 없습니다."),

  /** 비활성 또는 시행 전 약관 버전을 신규 동의에 사용한 경우이다. */
  TERM_VERSION_INACTIVE(HttpStatus.CONFLICT, "CONSENT_409_001", "현재 동의할 수 없는 약관 버전입니다."),

  /** 최초 등록 요청에서 현재 적용되는 필수 약관 동의가 빠진 경우이다. */
  REQUIRED_CONSENT_MISSING(HttpStatus.FORBIDDEN, "CONSENT_403_001", "필수 동의가 필요합니다."),

  /** 인증 사용자가 요청 아동과 연결된 보호자가 아닌 경우이다. */
  CONSENT_ACTOR_NOT_GUARDIAN(HttpStatus.FORBIDDEN, "CONSENT_403_002", "아동의 동의를 처리할 권한이 없습니다."),

  /** 약관 적용 범위, 중복 약관 또는 아동 식별자 조합이 유효하지 않은 경우이다. */
  CONSENT_REQUEST_INVALID(HttpStatus.BAD_REQUEST, "CONSENT_400_001", "동의 요청이 유효하지 않습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ConsentErrorCode(HttpStatus httpStatus, String code, String message) {
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
