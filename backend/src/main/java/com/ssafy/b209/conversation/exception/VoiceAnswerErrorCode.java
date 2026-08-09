package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 음성 답변 업로드 API가 공개하는 검증·상태·멱등성 오류 코드다. */
public enum VoiceAnswerErrorCode implements ErrorCode {
  INVALID_METADATA(
      HttpStatus.BAD_REQUEST, "VOICE_ANSWER_METADATA_INVALID", "음성 답변 metadata가 유효하지 않습니다."),
  CONVERSATION_NOT_FOUND(HttpStatus.NOT_FOUND, "CONVERSATION_NOT_FOUND", "대화 세션을 찾을 수 없습니다."),
  QUESTION_MESSAGE_NOT_FOUND(
      HttpStatus.NOT_FOUND, "QUESTION_MESSAGE_NOT_FOUND", "질문 메시지를 찾을 수 없습니다."),
  CONVERSATION_ACCESS_DENIED(
      HttpStatus.FORBIDDEN, "CONVERSATION_ACCESS_DENIED", "대화에 접근할 권한이 없습니다."),
  VOICE_CONSENT_REQUIRED(HttpStatus.FORBIDDEN, "VOICE_CONSENT_REQUIRED", "음성 처리 동의가 필요합니다."),
  CONVERSATION_NOT_CONVERSING(
      HttpStatus.CONFLICT, "CONVERSATION_NOT_CONVERSING", "현재 상태에서는 대화를 진행할 수 없습니다."),
  IDEMPOTENCY_IN_PROGRESS(
      HttpStatus.CONFLICT, "VOICE_ANSWER_IN_PROGRESS", "동일한 음성 답변 요청을 처리 중입니다."),
  IDEMPOTENCY_UNAVAILABLE(
      HttpStatus.SERVICE_UNAVAILABLE, "IDEMPOTENCY_UNAVAILABLE", "중복 요청 보호 기능을 사용할 수 없습니다."),
  VOICE_ANSWER_STORAGE_CONFLICT(
      HttpStatus.CONFLICT, "VOICE_ANSWER_STORAGE_CONFLICT", "음성 답변 저장 요청이 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  VoiceAnswerErrorCode(HttpStatus httpStatus, String code, String message) {
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
