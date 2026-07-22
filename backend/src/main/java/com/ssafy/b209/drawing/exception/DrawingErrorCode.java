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
  DRAWING_SESSION_CREATION_CONFLICT(HttpStatus.CONFLICT, "DRAWING_409_003", "그림 활동 생성 요청이 충돌했습니다."),
  /** 그림 활동 세션이 없거나 삭제된 경우다. */
  DRAWING_SESSION_NOT_FOUND(HttpStatus.NOT_FOUND, "DRAWING_404_003", "그림 활동을 찾을 수 없습니다."),
  /** 그림 활동 세션의 상태 또는 단계가 스냅샷 업로드를 허용하지 않는 경우다. */
  DRAWING_SESSION_NOT_UPLOADABLE(
      HttpStatus.CONFLICT, "DRAWING_409_004", "현재 상태에서는 그림을 업로드할 수 없습니다."),
  /** 업로드할 이미지 파일이 누락된 경우다. */
  DRAWING_SNAPSHOT_FILE_REQUIRED(HttpStatus.BAD_REQUEST, "DRAWING_400_005", "업로드할 그림 파일이 필요합니다."),
  /** 스냅샷 유형, 버전 또는 캡처 시각이 유효하지 않은 경우다. */
  DRAWING_SNAPSHOT_METADATA_INVALID(
      HttpStatus.BAD_REQUEST, "DRAWING_400_006", "그림 스냅샷 정보가 올바르지 않습니다."),
  /** 같은 세션·유형·버전의 스냅샷이 이미 존재하는 경우다. */
  DRAWING_SNAPSHOT_SEQUENCE_CONFLICT(
      HttpStatus.CONFLICT, "DRAWING_409_005", "같은 순서의 그림 스냅샷이 이미 존재합니다."),
  /** 같은 세션에 최종 스냅샷이 이미 존재하는 경우다. */
  DRAWING_FINAL_SNAPSHOT_EXISTS(HttpStatus.CONFLICT, "DRAWING_409_006", "최종 그림 스냅샷이 이미 존재합니다."),
  /** 파일 또는 Metadata를 저장하는 중 복구할 수 없는 오류가 발생한 경우다. */
  DRAWING_SNAPSHOT_STORAGE_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_001", "그림 스냅샷 저장 중 오류가 발생했습니다."),
  /** 동시 요청으로 스냅샷 Metadata의 DB 제약이 충돌한 경우다. */
  DRAWING_SNAPSHOT_CREATION_CONFLICT(
      HttpStatus.CONFLICT, "DRAWING_409_007", "그림 스냅샷 저장 요청이 충돌했습니다."),
  /** 저장된 그림 초안을 찾을 수 없는 경우다. */
  DRAWING_DRAFT_NOT_FOUND(HttpStatus.NOT_FOUND, "DRAWING_404_004", "저장된 그림 초안이 없습니다."),
  /** 현재 세션 상태나 단계에서 초안을 저장할 수 없는 경우다. */
  DRAWING_DRAFT_NOT_ALLOWED(HttpStatus.CONFLICT, "DRAWING_409_008", "현재 상태에서는 그림 초안을 저장할 수 없습니다."),
  /** 마지막 이벤트 순서가 현재 초안과 같은 경우다. */
  DRAWING_DRAFT_VERSION_CONFLICT(
      HttpStatus.CONFLICT, "DRAWING_409_009", "같은 순서의 그림 초안이 이미 저장되어 있습니다."),
  /** 마지막 이벤트 순서가 현재 초안보다 이전인 경우다. */
  STALE_DRAWING_DRAFT_VERSION(HttpStatus.CONFLICT, "DRAWING_409_010", "더 최근의 그림 초안이 이미 저장되어 있습니다."),
  /** 동시 요청으로 초안 Metadata 저장이 충돌한 경우다. */
  DRAWING_DRAFT_SAVE_CONFLICT(HttpStatus.CONFLICT, "DRAWING_409_011", "그림 초안 저장 요청이 충돌했습니다."),
  /** 초안 Metadata 저장 과정에서 복구할 수 없는 오류가 발생한 경우다. */
  DRAWING_DRAFT_STORAGE_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_002", "그림 초안 저장 중 오류가 발생했습니다."),
  /** 초안 미리보기 파일이 누락된 경우다. */
  DRAWING_DRAFT_FILE_REQUIRED(HttpStatus.BAD_REQUEST, "DRAWING_400_007", "초안 미리보기 파일이 필요합니다."),
  /** 초안 복구 기준 Metadata가 누락되거나 유효하지 않은 경우다. */
  DRAWING_DRAFT_METADATA_INVALID(HttpStatus.BAD_REQUEST, "DRAWING_400_008", "그림 초안 정보가 올바르지 않습니다."),
  /** 아동에게 삭제되지 않은 진행 중 그림 활동 세션이 없는 경우다. */
  ACTIVE_DRAWING_SESSION_NOT_FOUND(HttpStatus.NOT_FOUND, "DRAWING_404_005", "진행 중인 그림 활동이 없습니다."),
  /** 한 아동에게 진행 중 그림 활동 세션이 둘 이상 존재해 단일 세션을 결정할 수 없는 경우다. */
  MULTIPLE_ACTIVE_DRAWING_SESSIONS(
      HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_003", "진행 중인 그림 활동 데이터가 중복되었습니다.");

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
