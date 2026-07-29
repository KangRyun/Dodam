package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 질문 건너뛰기(CONV-08) 요청에서 공개하는 오류 코드다. */
public enum QuestionSkipErrorCode implements ErrorCode {
  CONVERSATION_NOT_FOUND(HttpStatus.NOT_FOUND, "CONVERSATION_NOT_FOUND", "대화 세션을 찾을 수 없습니다."),
  QUESTION_MESSAGE_NOT_FOUND(
      HttpStatus.NOT_FOUND, "QUESTION_MESSAGE_NOT_FOUND", "대화에서 해당 질문을 찾을 수 없습니다."),
  CONVERSATION_NOT_CONVERSING(
      HttpStatus.CONFLICT, "CONVERSATION_NOT_CONVERSING", "현재 상태에서는 대화를 진행할 수 없습니다."),
  QUESTION_SKIP_RETURN_TO_DRAWING_UNSUPPORTED(
      HttpStatus.CONFLICT,
      "QUESTION_SKIP_RETURN_TO_DRAWING_UNSUPPORTED",
      "건너뛰면서 그림 단계로 돌아가는 기능은 아직 제공하지 않습니다."),
  QUESTION_SKIP_CONFLICT(
      HttpStatus.CONFLICT, "QUESTION_SKIP_CONFLICT", "질문 건너뛰기 요청이 처리 중이거나 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  QuestionSkipErrorCode(HttpStatus httpStatus, String code, String message) {
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
