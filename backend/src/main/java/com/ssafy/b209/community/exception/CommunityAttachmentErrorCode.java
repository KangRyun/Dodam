package com.ssafy.b209.community.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 커뮤니티 첨부 이미지 업로드·연결 과정의 공개 오류 코드다. */
public enum CommunityAttachmentErrorCode implements ErrorCode {
  FILE_REQUIRED(HttpStatus.BAD_REQUEST, "COMMUNITY_ATTACHMENT_FILE_REQUIRED", "첨부 이미지가 필요합니다."),
  FILE_TOO_LARGE(
      HttpStatus.PAYLOAD_TOO_LARGE,
      "COMMUNITY_ATTACHMENT_FILE_TOO_LARGE",
      "첨부 이미지는 5 MiB 이하여야 합니다."),
  NOT_FOUND(HttpStatus.NOT_FOUND, "COMMUNITY_ATTACHMENT_NOT_FOUND", "첨부 이미지를 찾을 수 없습니다."),
  NOT_ATTACHABLE(
      HttpStatus.CONFLICT, "COMMUNITY_ATTACHMENT_NOT_ATTACHABLE", "만료되었거나 이미 사용된 첨부 이미지입니다."),
  DUPLICATED(
      HttpStatus.BAD_REQUEST, "COMMUNITY_ATTACHMENT_DUPLICATED", "같은 첨부 이미지를 중복해서 사용할 수 없습니다."),
  UPLOAD_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "COMMUNITY_ATTACHMENT_UPLOAD_FAILED", "첨부 이미지 저장에 실패했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  CommunityAttachmentErrorCode(HttpStatus httpStatus, String code, String message) {
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
