package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 289 STT 처리 과정에서만 사용하는 상태·저장 오류 코드다. */
public enum SttProcessingErrorCode implements ErrorCode {
  STT_MESSAGE_NOT_FOUND(HttpStatus.NOT_FOUND, "STT_MESSAGE_NOT_FOUND", "음성 답변 메시지를 찾을 수 없습니다."),
  INVALID_STT_MESSAGE(HttpStatus.CONFLICT, "INVALID_STT_MESSAGE", "STT 처리할 수 없는 음성 답변입니다."),
  CONVERSATION_NOT_CONVERSING(
      HttpStatus.CONFLICT, "CONVERSATION_NOT_CONVERSING", "현재 상태에서는 대화를 진행할 수 없습니다."),
  STT_AUDIO_NOT_AVAILABLE(
      HttpStatus.SERVICE_UNAVAILABLE, "STT_AUDIO_NOT_AVAILABLE", "STT 처리용 음성 파일을 읽을 수 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  SttProcessingErrorCode(HttpStatus httpStatus, String code, String message) {
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
