package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 대화 세션 시작 API에서 공개하는 확정 오류 코드다. */
public enum ConversationStartErrorCode implements ErrorCode {
  UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "UNAUTHORIZED", "인증이 필요합니다."),
  RESOURCE_NOT_FOUND(HttpStatus.NOT_FOUND, "RESOURCE_NOT_FOUND", "그림 활동을 찾을 수 없습니다."),
  RESOURCE_OWNERSHIP_DENIED(
      HttpStatus.NOT_FOUND, "RESOURCE_OWNERSHIP_DENIED", "접근할 수 없는 그림 활동입니다."),
  REQUIRED_CONSENT_MISSING(HttpStatus.FORBIDDEN, "REQUIRED_CONSENT_MISSING", "필수 동의가 필요합니다."),
  INVALID_STATE_TRANSITION(
      HttpStatus.CONFLICT, "INVALID_STATE_TRANSITION", "현재 상태에서는 대화를 시작할 수 없습니다."),
  ACTIVE_CONVERSATION_EXISTS(
      HttpStatus.CONFLICT, "ACTIVE_CONVERSATION_EXISTS", "진행 중인 대화가 이미 있습니다."),
  IDEMPOTENCY_KEY_REUSED(
      HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED", "동일한 멱등성 키가 다른 요청에 사용되었습니다."),
  CONVERSATION_START_CONFLICT(
      HttpStatus.CONFLICT, "CONVERSATION_START_CONFLICT", "대화 세션 생성 요청이 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ConversationStartErrorCode(HttpStatus httpStatus, String code, String message) {
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
