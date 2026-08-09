package com.ssafy.b209.conversation.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/**
 * CONV-04 질문 TTS 음성 생성 과정에서만 사용하는 안전한 오류 코드다.
 *
 * <p>메시지 없음과 접근 거부는 STT 상태 조회·음성 재생과 동일한 {@link ConversationMessageStatusErrorCode}를 재사용한다. 내부 저장
 * key·절대 경로·AI 응답 원문은 응답에 담지 않는다.
 */
public enum QuestionTtsErrorCode implements ErrorCode {
  TTS_NOT_APPLICABLE(HttpStatus.BAD_REQUEST, "TTS_NOT_APPLICABLE", "AI 질문 메시지에만 음성을 생성할 수 있습니다."),
  TTS_GENERATION_IN_PROGRESS(
      HttpStatus.CONFLICT, "TTS_GENERATION_IN_PROGRESS", "이미 음성 생성이 진행 중입니다."),
  TTS_FAILED(HttpStatus.BAD_GATEWAY, "TTS_FAILED", "질문 음성 생성에 실패했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  QuestionTtsErrorCode(HttpStatus httpStatus, String code, String message) {
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
