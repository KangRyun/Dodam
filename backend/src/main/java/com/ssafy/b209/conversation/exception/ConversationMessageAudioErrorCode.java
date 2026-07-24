package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/**
 * 대화 음성 답변 원본 재생 프록시 스트리밍이 공개하는 안전한 오류 코드다.
 *
 * <p>메시지 없음과 접근 거부는 STT 상태 조회와 동일한 {@link ConversationMessageStatusErrorCode}를 재사용하고, 이 열거는 재생할 원본
 * 음성이 존재하지 않거나 삭제된 경우만을 표현한다. 내부 저장 key·절대 경로·삭제 사유는 응답에 담지 않는다.
 */
public enum ConversationMessageAudioErrorCode implements ErrorCode {
  CONVERSATION_AUDIO_NOT_AVAILABLE(
      HttpStatus.NOT_FOUND, "CONVERSATION_AUDIO_NOT_AVAILABLE", "재생할 음성 파일을 찾을 수 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ConversationMessageAudioErrorCode(HttpStatus httpStatus, String code, String message) {
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
