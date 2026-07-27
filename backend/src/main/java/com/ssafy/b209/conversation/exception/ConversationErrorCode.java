package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 대화 질문 생성에서 공개 가능한 안전한 오류 코드다. */
public enum ConversationErrorCode implements ErrorCode {
  CONVERSATION_SESSION_NOT_FOUND(HttpStatus.NOT_FOUND, "CONVERSATION_404_001", "대화 세션을 찾을 수 없습니다."),
  QUESTION_LIMIT_REACHED(HttpStatus.CONFLICT, "CONVERSATION_409_001", "질문 가능 횟수를 모두 사용했습니다."),
  CONVERSATION_ALREADY_COMPLETED(
      HttpStatus.CONFLICT, "CONVERSATION_ALREADY_COMPLETED", "이미 종료된 대화입니다."),
  CONVERSATION_ACCESS_DENIED(
      HttpStatus.FORBIDDEN, "CONVERSATION_ACCESS_DENIED", "대화에 접근할 권한이 없습니다."),
  PREFERRED_RESPONSE_MODE_INVALID(
      HttpStatus.UNPROCESSABLE_ENTITY, "PREFERRED_RESPONSE_MODE_INVALID", "지원하지 않는 응답 방식입니다."),
  QUESTION_MESSAGE_NOT_FOUND(
      HttpStatus.NOT_FOUND, "QUESTION_MESSAGE_NOT_FOUND", "질문 메시지를 찾을 수 없습니다."),
  AI_SAFETY_POLICY_BLOCKED(
      HttpStatus.UNPROCESSABLE_ENTITY, "AI_SAFETY_POLICY_BLOCKED", "안전한 질문을 생성할 수 없습니다."),
  FALLBACK_QUESTION_NOT_FOUND(
      HttpStatus.SERVICE_UNAVAILABLE, "CONVERSATION_503_001", "질문을 준비할 수 없습니다."),
  QUESTION_STORAGE_CONFLICT(HttpStatus.CONFLICT, "CONVERSATION_409_002", "질문 저장 요청이 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ConversationErrorCode(HttpStatus httpStatus, String code, String message) {
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
