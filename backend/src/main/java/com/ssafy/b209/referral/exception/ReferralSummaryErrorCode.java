package com.ssafy.b209.referral.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 전문가 의뢰 요약이 공개하는 안전한 오류 코드다. */
public enum ReferralSummaryErrorCode implements ErrorCode {
  /** 보호자와 아동의 연결이 없거나 아동이 활성 상태가 아닌 경우다. */
  REFERRAL_ACCESS_DENIED(
      HttpStatus.FORBIDDEN, "REFERRAL_ACCESS_DENIED", "아이의 의뢰 요약에 접근할 권한이 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ReferralSummaryErrorCode(HttpStatus httpStatus, String code, String message) {
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
