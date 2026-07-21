package com.ssafy.b209.drawing.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 그림 활동 세션 생성 과정에서 클라이언트에 반환하는 도메인 오류 코드를 정의한다. */
public enum DrawingErrorCode implements ErrorCode {
  /** 아동을 찾을 수 없는 경우다. */
  CHILD_NOT_FOUND(HttpStatus.NOT_FOUND, "DRAWING_404_001", "아동 정보를 찾을 수 없습니다."),
  /** 그림 활동 유형을 찾을 수 없는 경우다. */
  DRAWING_TYPE_NOT_FOUND(HttpStatus.NOT_FOUND, "DRAWING_404_002", "그림 활동 유형을 찾을 수 없습니다."),
  /** 아동이 현재 선택할 수 없는 그림 활동 유형인 경우다. */
  DRAWING_TYPE_NOT_AVAILABLE(HttpStatus.BAD_REQUEST, "DRAWING_400_001", "현재 선택할 수 없는 그림 활동 유형입니다."),
  /** 캔버스 설정이 유효하지 않은 경우다. */
  INVALID_CANVAS_CONFIGURATION(HttpStatus.BAD_REQUEST, "DRAWING_400_002", "캔버스 설정이 올바르지 않습니다."),
  /** 멱등성 키가 누락된 경우다. */
  IDEMPOTENCY_KEY_REQUIRED(HttpStatus.BAD_REQUEST, "DRAWING_400_003", "Idempotency-Key가 필요합니다."),
  /** 멱등성 키 형식이 유효하지 않은 경우다. */
  IDEMPOTENCY_KEY_INVALID(
      HttpStatus.BAD_REQUEST, "DRAWING_400_004", "Idempotency-Key 형식이 올바르지 않습니다."),
  /** 아동에게 진행 중인 그림 활동 세션이 이미 있는 경우다. */
  ACTIVE_DRAWING_SESSION_EXISTS(HttpStatus.CONFLICT, "DRAWING_409_001", "진행 중인 그림 활동이 이미 존재합니다."),
  /** 같은 멱등성 키가 다른 요청에 사용된 경우다. */
  IDEMPOTENCY_KEY_CONFLICT(
      HttpStatus.CONFLICT, "DRAWING_409_002", "동일한 Idempotency-Key가 다른 요청에 사용되었습니다."),
  /** 그림 활동 세션 생성 요청이 충돌한 경우다. */
  DRAWING_SESSION_CREATION_CONFLICT(HttpStatus.CONFLICT, "DRAWING_409_003", "그림 활동 생성 요청이 충돌했습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  DrawingErrorCode(HttpStatus httpStatus, String code, String message) {
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
