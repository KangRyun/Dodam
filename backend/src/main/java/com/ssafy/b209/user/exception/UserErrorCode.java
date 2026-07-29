package com.ssafy.b209.user.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 사용자 API에서 클라이언트에 반환하는 오류 코드를 정의한다. */
public enum UserErrorCode implements ErrorCode {
  /** Onboarding에서 허용하지 않는 역할(예: {@code ADMIN})을 요청한 경우다. */
  ROLE_NOT_ALLOWED(HttpStatus.BAD_REQUEST, "USER_400_001", "선택할 수 없는 역할입니다."),

  /** 인증된 사용자 식별자에 해당하는 사용자를 찾을 수 없는 경우다. */
  USER_NOT_FOUND(HttpStatus.NOT_FOUND, "USER_404_001", "사용자 정보를 찾을 수 없습니다."),

  /** 회원 탈퇴 확인 문자열이 정확한 값과 일치하지 않는 경우다. */
  WITHDRAWAL_CONFIRMATION_MISMATCH(
      HttpStatus.BAD_REQUEST, "USER_400_002", "회원 탈퇴 확인 값이 올바르지 않습니다."),

  /**
   * 전문가 프로필이 있는 사용자가 탈퇴를 시도한 경우다 (S15P11B209-728).
   *
   * <p>{@code expert_profiles.users_id}가 {@code ON DELETE RESTRICT}라 그대로 두면 DB 제약 위반이 500으로 새어 나간다.
   * 전문가 프로필은 자격 심사 이력(검증 상태·경력)을 담고 있어 탈퇴 처리와 함께 지울지, 보존할지가 정책 결정 사항이라
   * 임의로 삭제하지 않는다. 그 결정이 날 때까지는 <b>왜 막혔는지 알 수 있는 4xx</b>로 돌려준다.
   */
  WITHDRAWAL_BLOCKED_BY_EXPERT_PROFILE(
      HttpStatus.CONFLICT, "USER_409_001", "전문가 프로필이 있어 탈퇴할 수 없습니다. 관리자에게 문의해 주세요.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  UserErrorCode(HttpStatus httpStatus, String code, String message) {
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
