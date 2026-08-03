package com.ssafy.b209.community.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 댓글 작성·수정·삭제에서 사용하는 공개 오류 코드다. */
public enum CommunityCommentErrorCode implements ErrorCode {
  COMMENT_NOT_FOUND(HttpStatus.NOT_FOUND, "COMMENT_NOT_FOUND", "댓글을 찾을 수 없습니다."),
  COMMENT_WRITE_NOT_ALLOWED(
      HttpStatus.FORBIDDEN, "COMMENT_WRITE_NOT_ALLOWED", "해당 게시글에 댓글을 작성할 권한이 없습니다."),
  COMMENT_ACCESS_DENIED(HttpStatus.FORBIDDEN, "COMMENT_ACCESS_DENIED", "댓글을 변경할 권한이 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommunityCommentErrorCode(HttpStatus httpStatus, String code, String message) {
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
