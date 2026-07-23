package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 선택형 답변 저장 API가 공개하는 검증·권한·상태·멱등성 오류 코드다. */
public enum OptionAnswerErrorCode implements ErrorCode {
  INVALID_REQUEST(HttpStatus.BAD_REQUEST, "OPTION_ANSWER_INVALID", "선택형 답변 요청이 유효하지 않습니다."),
  CONVERSATION_NOT_FOUND(HttpStatus.NOT_FOUND, "CONVERSATION_NOT_FOUND", "대화 세션을 찾을 수 없습니다."),
  QUESTION_MESSAGE_NOT_FOUND(
      HttpStatus.NOT_FOUND, "QUESTION_MESSAGE_NOT_FOUND", "질문 메시지를 찾을 수 없습니다."),
  CONVERSATION_ACCESS_DENIED(
      HttpStatus.FORBIDDEN, "CONVERSATION_ACCESS_DENIED", "대화에 접근할 권한이 없습니다."),
  CONSENT_REQUIRED(HttpStatus.FORBIDDEN, "CONSENT_REQUIRED", "필수 동의가 필요합니다."),
  CONVERSATION_NOT_CONVERSING(
      HttpStatus.CONFLICT, "CONVERSATION_NOT_CONVERSING", "현재 상태에서는 선택형 답변을 저장할 수 없습니다."),
  CONVERSATION_ALREADY_COMPLETED(
      HttpStatus.CONFLICT, "CONVERSATION_ALREADY_COMPLETED", "이미 종료된 대화입니다."),
  ANSWER_ALREADY_SUBMITTED(
      HttpStatus.CONFLICT, "ANSWER_ALREADY_SUBMITTED", "해당 질문에는 이미 답변이 저장되었습니다."),
  OPTION_NOT_ALLOWED(HttpStatus.CONFLICT, "OPTION_NOT_ALLOWED", "질문에 포함되지 않은 선택지입니다."),
  OPTION_ANSWER_STORAGE_CONFLICT(
      HttpStatus.CONFLICT, "OPTION_ANSWER_STORAGE_CONFLICT", "선택형 답변 저장 요청이 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  OptionAnswerErrorCode(HttpStatus httpStatus, String code, String message) {
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
