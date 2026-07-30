package com.ssafy.b209.expert.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 전문가 프로필과 자격 관리 과정에서 클라이언트에 공개할 오류를 정의한다. */
public enum ExpertErrorCode implements ErrorCode {
  /** 동일한 사용자에게 전문가 프로필이 이미 존재하는 경우다. */
  EXPERT_PROFILE_ALREADY_EXISTS(
      HttpStatus.CONFLICT, "EXPERT_PROFILE_ALREADY_EXISTS", "전문가 프로필이 이미 등록되어 있습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ExpertErrorCode(HttpStatus httpStatus, String code, String message) {
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
