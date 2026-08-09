package com.ssafy.b209.expert.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** 전문가 프로필과 자격 관리 과정에서 클라이언트에 공개할 오류를 정의한다. */
public enum ExpertErrorCode implements ErrorCode {
  /** 요청한 전문가 프로필이 존재하지 않는 경우다. */
  EXPERT_PROFILE_NOT_FOUND(HttpStatus.NOT_FOUND, "EXPERT_PROFILE_NOT_FOUND", "전문가 프로필을 찾을 수 없습니다."),
  /** 검증 전 프로필을 소유자 외 사용자가 조회하려는 경우다. */
  EXPERT_NOT_VERIFIED(HttpStatus.FORBIDDEN, "EXPERT_NOT_VERIFIED", "검증이 완료되지 않은 전문가 프로필입니다."),
  /** 동일한 사용자에게 전문가 프로필이 이미 존재하는 경우다. */
  EXPERT_PROFILE_ALREADY_EXISTS(
      HttpStatus.CONFLICT, "EXPERT_PROFILE_ALREADY_EXISTS", "전문가 프로필이 이미 등록되어 있습니다."),
  /** 수정 결과의 대상 연령 범위가 올바르지 않은 경우이다. */
  EXPERT_PROFILE_INVALID(
      HttpStatus.BAD_REQUEST, "EXPERT_PROFILE_INVALID", "전문가 프로필 입력값이 올바르지 않습니다."),
  /** 자격 증빙 파일이 없거나 형식과 Signature가 허용 범위가 아닌 경우이다. */
  CREDENTIAL_FILE_INVALID(
      HttpStatus.BAD_REQUEST, "CREDENTIAL_FILE_INVALID", "PDF, JPEG 또는 PNG 자격 증빙 파일이 필요합니다."),
  /** 자격 증빙 파일의 실제 Byte 크기가 10MiB를 초과한 경우이다. */
  CREDENTIAL_FILE_TOO_LARGE(
      HttpStatus.PAYLOAD_TOO_LARGE, "CREDENTIAL_FILE_TOO_LARGE", "자격 증빙 파일은 10MiB 이하여야 합니다."),
  /** 검증된 자격 증빙 파일을 Storage에 저장하지 못한 경우이다. */
  CREDENTIAL_STORAGE_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "CREDENTIAL_STORAGE_FAILED", "자격 증빙 파일을 저장하지 못했습니다."),
  /** 요청한 자격이 없거나 로그인 전문가의 소유가 아닌 경우다. */
  CREDENTIAL_NOT_FOUND(HttpStatus.NOT_FOUND, "CREDENTIAL_NOT_FOUND", "전문가 자격 정보를 찾을 수 없습니다."),
  /** 관리자 검토가 시작되거나 끝난 자격을 사용자가 삭제하려는 경우다. */
  CREDENTIAL_DELETE_NOT_ALLOWED(
      HttpStatus.CONFLICT, "CREDENTIAL_DELETE_NOT_ALLOWED", "검토 이력이 있는 자격 정보는 삭제할 수 없습니다."),
  /** 승인·반려 상태와 사유 또는 선택 자격 조합이 올바르지 않은 경우다. */
  EXPERT_VERIFICATION_REQUEST_INVALID(
      HttpStatus.BAD_REQUEST, "EXPERT_VERIFICATION_REQUEST_INVALID", "전문가 검증 요청이 올바르지 않습니다.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  ExpertErrorCode(HttpStatus httpStatus, String code, String message) {
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
