package com.ssafy.b209.community.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 커뮤니티 게시글 공개 상세 조회에서 반환하는 확정 오류 코드다. */
public enum CommunityPostDetailErrorCode implements ErrorCode {
  /** 게시글이 없거나 일반 공개 조건을 만족하지 않는 경우다. */
  POST_NOT_FOUND(HttpStatus.NOT_FOUND, "POST_NOT_FOUND", "게시글을 찾을 수 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommunityPostDetailErrorCode(HttpStatus httpStatus, String code, String message) {
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
