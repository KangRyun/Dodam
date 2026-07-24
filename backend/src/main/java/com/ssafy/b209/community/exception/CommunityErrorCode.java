package com.ssafy.b209.community.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 커뮤니티 공개 API에서 공통 오류보다 구체적으로 반환해야 하는 오류 코드다. */
public enum CommunityErrorCode implements ErrorCode {
  /** 목록 Query Parameter가 최신 COMM-01 계약을 만족하지 않는 경우다. */
  VALIDATION_FAILED(HttpStatus.BAD_REQUEST, "VALIDATION_FAILED", "요청 값이 올바르지 않습니다."),

  /** 사용자 역할이 해당 게시글 유형을 작성할 수 없는 경우다. */
  POST_TYPE_NOT_ALLOWED(HttpStatus.FORBIDDEN, "POST_TYPE_NOT_ALLOWED", "해당 게시글 유형을 작성할 권한이 없습니다."),

  /** 게시글을 작성할 역할이 확정되지 않아 접근이 거부된 경우다. */
  POST_ACCESS_DENIED(HttpStatus.FORBIDDEN, "POST_ACCESS_DENIED", "게시글을 작성할 권한이 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommunityErrorCode(HttpStatus httpStatus, String code, String message) {
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
