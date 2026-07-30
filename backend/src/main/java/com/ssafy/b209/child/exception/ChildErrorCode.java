package com.ssafy.b209.child.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 아동 프로필 API에서 클라이언트에 반환하는 오류 코드를 정의한다. */
public enum ChildErrorCode implements ErrorCode {
  /** 아동이 없거나 삭제됐거나 요청 보호자에게 연결되지 않은 경우다. */
  CHILD_NOT_FOUND(HttpStatus.NOT_FOUND, "CHILD_404_001", "아동 정보를 찾을 수 없습니다."),

  /** 등록일 기준 만 나이가 허용 범위(만 4~12세)를 벗어난 경우다. */
  CHILD_AGE_OUT_OF_RANGE(
      HttpStatus.BAD_REQUEST, "CHILD_400_001", "아동 나이는 만 4세 이상 12세 이하만 등록할 수 있습니다."),

  /** 삭제 확인 문자열이 일치하지 않는 경우다. */
  CHILD_DELETION_CONFIRMATION_MISMATCH(
      HttpStatus.BAD_REQUEST, "CHILD_400_002", "아동 삭제 확인 값이 올바르지 않습니다."),

  /** 다른 보호자가 연결되어 전체 프로필 삭제를 허용할 수 없는 경우다. */
  CHILD_HAS_OTHER_GUARDIAN(HttpStatus.CONFLICT, "CHILD_409_001", "다른 보호자가 연결된 아동은 삭제할 수 없습니다."),

  /** 완료·건너뛰기 상태를 되돌리거나 허용 순서를 건너뛰는 Tutorial 변경 요청이다. */
  CHILD_TUTORIAL_STATUS_CONFLICT(HttpStatus.CONFLICT, "CHILD_409_002", "변경할 수 없는 Tutorial 상태입니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ChildErrorCode(HttpStatus httpStatus, String code, String message) {
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
