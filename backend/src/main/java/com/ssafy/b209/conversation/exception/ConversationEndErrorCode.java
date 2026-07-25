package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 대화 종료 요청에서 공개하는 상태 및 최신 질문 검증 오류 코드다. */
public enum ConversationEndErrorCode implements ErrorCode {
  CONVERSATION_NOT_FOUND(HttpStatus.NOT_FOUND, "CONVERSATION_NOT_FOUND", "대화 세션을 찾을 수 없습니다."),
  CONVERSATION_NOT_CONVERSING(
      HttpStatus.CONFLICT, "CONVERSATION_NOT_CONVERSING", "현재 상태에서는 대화를 종료할 수 없습니다."),
  CONVERSATION_LAST_QUESTION_MISMATCH(
      HttpStatus.CONFLICT, "CONVERSATION_LAST_QUESTION_MISMATCH", "마지막 질문이 현재 대화 상태와 일치하지 않습니다."),
  CONVERSATION_END_CONFLICT(
      HttpStatus.CONFLICT, "CONVERSATION_END_CONFLICT", "대화 종료 요청이 처리 중이거나 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ConversationEndErrorCode(HttpStatus httpStatus, String code, String message) {
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
