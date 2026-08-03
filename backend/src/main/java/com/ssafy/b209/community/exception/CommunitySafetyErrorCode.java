package com.ssafy.b209.community.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 커뮤니티 신고·사용자 차단 계약에서 사용하는 오류 코드다. */
public enum CommunitySafetyErrorCode implements ErrorCode {
  COMPLAINT_ALREADY_EXISTS(
      HttpStatus.CONFLICT, "COMPLAINT_ALREADY_EXISTS", "동일한 대상과 사유의 신고가 이미 존재합니다."),
  USER_BLOCK_SELF_NOT_ALLOWED(
      HttpStatus.BAD_REQUEST, "USER_BLOCK_SELF_NOT_ALLOWED", "자기 자신은 차단할 수 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommunitySafetyErrorCode(HttpStatus httpStatus, String code, String message) {
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
