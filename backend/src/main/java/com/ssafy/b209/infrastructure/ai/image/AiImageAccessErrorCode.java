package com.ssafy.b209.infrastructure.ai.image;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** AI 내부 이미지 조회에서 Token 상태와 Infrastructure 장애를 구분하는 안전한 오류 코드다. */
public enum AiImageAccessErrorCode implements ErrorCode {
  /** Token이 잘못됐거나 만료·재사용됐거나 대상 이미지를 안전하게 조회할 수 없는 경우다. */
  IMAGE_ACCESS_NOT_FOUND(HttpStatus.NOT_FOUND, "AI_IMAGE_404_001", "조회할 이미지를 찾을 수 없습니다."),
  /** Redis 또는 이미지 Storage 장애로 일회성 조회를 처리할 수 없는 경우다. */
  IMAGE_ACCESS_UNAVAILABLE(
      HttpStatus.SERVICE_UNAVAILABLE, "AI_IMAGE_503_001", "이미지 조회 서비스를 사용할 수 없습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  AiImageAccessErrorCode(HttpStatus httpStatus, String code, String message) {
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
