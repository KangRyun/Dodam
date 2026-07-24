package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 대화 메시지 STT 처리 상태·변환 결과 조회가 공개하는 안전한 오류 코드다. */
public enum ConversationMessageStatusErrorCode implements ErrorCode {
  CONVERSATION_MESSAGE_NOT_FOUND(
      HttpStatus.NOT_FOUND, "CONVERSATION_MESSAGE_NOT_FOUND", "대화 메시지를 찾을 수 없습니다."),
  CONVERSATION_ACCESS_DENIED(
      HttpStatus.FORBIDDEN, "CONVERSATION_ACCESS_DENIED", "대화에 접근할 권한이 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ConversationMessageStatusErrorCode(HttpStatus httpStatus, String code, String message) {
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
