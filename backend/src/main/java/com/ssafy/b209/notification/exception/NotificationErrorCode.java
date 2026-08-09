package com.ssafy.b209.notification.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 알림 도메인의 업무 오류 코드다. 명세 15.5의 오류 어휘를 코드로 옮긴 것이다. */
public enum NotificationErrorCode implements ErrorCode {

  /** metadata 또는 Push Token 값이 계약을 만족하지 못한 경우다. */
  DEVICE_TOKEN_INVALID(HttpStatus.BAD_REQUEST, "DEVICE_TOKEN_INVALID", "디바이스 토큰 요청이 올바르지 않습니다."),

  /** 해제 대상 기기 Token 또는 알림이 없는 경우다. */
  DEVICE_TOKEN_NOT_FOUND(HttpStatus.NOT_FOUND, "DEVICE_TOKEN_NOT_FOUND", "등록된 디바이스 토큰을 찾을 수 없습니다."),

  /** 알림이 없거나 이미 삭제된 경우다. 남의 알림도 존재를 숨기기 위해 같은 코드로 응답한다. */
  NOTIFICATION_NOT_FOUND(HttpStatus.NOT_FOUND, "NOTIFICATION_NOT_FOUND", "알림을 찾을 수 없습니다."),

  /** 수신자가 아닌 사용자가 알림을 조작하려는 경우다. 조회 경로에서는 존재를 숨기므로 사용하지 않는다. */
  NOTIFICATION_ACCESS_DENIED(HttpStatus.FORBIDDEN, "NOTIFICATION_ACCESS_DENIED", "알림에 접근할 수 없습니다."),

  /** 암호화 키가 구성되지 않아 Token을 안전하게 저장할 수 없는 경우다. */
  DEVICE_TOKEN_STORAGE_UNAVAILABLE(
      HttpStatus.SERVICE_UNAVAILABLE,
      "DEVICE_TOKEN_STORAGE_UNAVAILABLE",
      "디바이스 토큰 저장이 구성되지 않았습니다."),

  /** 다른 사용자에게 이미 등록된 Token을 재등록하려는 경우다. */
  DEVICE_TOKEN_ALREADY_REGISTERED(
      HttpStatus.CONFLICT, "DEVICE_TOKEN_ALREADY_REGISTERED", "이미 다른 계정에 등록된 디바이스 토큰입니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  NotificationErrorCode(HttpStatus httpStatus, String code, String message) {
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
