package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 질문 건너뛰기 API가 공개하는 권한·상태·질문 검증 오류 코드다. 형제 답변 API와 어휘를 정렬한다. */
public enum QuestionSkipErrorCode implements ErrorCode {
  CONVERSATION_NOT_FOUND(HttpStatus.NOT_FOUND, "CONVERSATION_NOT_FOUND", "대화 세션을 찾을 수 없습니다."),
  QUESTION_MESSAGE_NOT_FOUND(
      HttpStatus.NOT_FOUND, "QUESTION_MESSAGE_NOT_FOUND", "질문 메시지를 찾을 수 없습니다."),
  CONVERSATION_ACCESS_DENIED(
      HttpStatus.FORBIDDEN, "CONVERSATION_ACCESS_DENIED", "대화에 접근할 권한이 없습니다."),
  CONSENT_REQUIRED(HttpStatus.FORBIDDEN, "CONSENT_REQUIRED", "필수 동의가 필요합니다."),
  CONVERSATION_NOT_CONVERSING(
      HttpStatus.CONFLICT, "CONVERSATION_NOT_CONVERSING", "현재 상태에서는 질문을 건너뛸 수 없습니다."),
  CONVERSATION_ALREADY_COMPLETED(
      HttpStatus.CONFLICT, "CONVERSATION_ALREADY_COMPLETED", "이미 종료된 대화입니다."),
  ANSWER_ALREADY_SUBMITTED(
      HttpStatus.CONFLICT, "ANSWER_ALREADY_SUBMITTED", "이미 답변한 질문은 건너뛸 수 없습니다.");

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
