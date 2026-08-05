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
  /** 마지막 이벤트 순서와 클라이언트 저장 시각이 현재 초안과 모두 같은 경우다. */
  DRAWING_DRAFT_VERSION_CONFLICT(
      HttpStatus.CONFLICT, "DRAWING_409_009", "같은 버전의 그림 초안이 이미 저장되어 있습니다."),
  /** 마지막 이벤트 순서가 이전이거나 같은 순서에서 저장 시각이 이전인 경우다. */
  STALE_DRAWING_DRAFT_VERSION(HttpStatus.CONFLICT, "DRAWING_409_010", "더 최근의 그림 초안이 이미 저장되어 있습니다."),
  /** 동시 요청으로 초안 Metadata 저장이 충돌한 경우다. */
  DRAWING_DRAFT_SAVE_CONFLICT(HttpStatus.CONFLICT, "DRAWING_409_011", "그림 초안 저장 요청이 충돌했습니다."),
  /** 동일 Draft 멱등 키가 다른 이미지 또는 canvasState에 재사용된 경우다. */
  DRAFT_IDEMPOTENCY_KEY_REUSED(
      HttpStatus.CONFLICT, "IDEMPOTENCY_KEY_REUSED", "동일한 멱등성 키가 다른 요청에 사용되었습니다."),
  /** 동일 Draft 요청의 선행 처리가 제한 시간 안에 완료되지 않은 경우다. */
  DRAFT_SAVE_IN_PROGRESS(
      HttpStatus.CONFLICT, "DRAFT_SAVE_IN_PROGRESS", "동일한 그림 초안 저장 요청이 처리 중입니다."),
  /** 초안 Metadata 저장 과정에서 복구할 수 없는 오류가 발생한 경우다. */
  DRAWING_DRAFT_STORAGE_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_002", "그림 초안 저장 중 오류가 발생했습니다."),
  /** 초안 미리보기 파일이 누락된 경우다. */
  DRAWING_DRAFT_FILE_REQUIRED(HttpStatus.BAD_REQUEST, "DRAWING_400_007", "초안 미리보기 파일이 필요합니다."),
  /** 초안 복구 기준 Metadata가 누락되거나 유효하지 않은 경우다. */
  DRAWING_DRAFT_METADATA_INVALID(HttpStatus.BAD_REQUEST, "DRAWING_400_008", "그림 초안 정보가 올바르지 않습니다."),
  /** 아동에게 삭제되지 않은 진행 중 그림 활동 세션이 없는 경우다. */
  ACTIVE_DRAWING_SESSION_NOT_FOUND(HttpStatus.NOT_FOUND, "DRAWING_404_005", "진행 중인 그림 활동이 없습니다."),
  /** 요청한 그림 파일 Metadata가 없는 경우다. */
  DRAWING_ASSET_NOT_FOUND(HttpStatus.NOT_FOUND, "DRAWING_404_006", "그림 파일을 찾을 수 없습니다."),
  /** 한 아동에게 진행 중 그림 활동 세션이 둘 이상 존재해 단일 세션을 결정할 수 없는 경우다. */
  MULTIPLE_ACTIVE_DRAWING_SESSIONS(
      HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_003", "진행 중인 그림 활동 데이터가 중복되었습니다."),
  /** 감정 선택과 건너뛰기 요청 조합이 유효하지 않은 경우다. */
  DRAWING_REFLECTION_INVALID(HttpStatus.BAD_REQUEST, "DRAWING_400_009", "그림 활동 감정 정보가 올바르지 않습니다."),
  /** 현재 세션 상태나 단계에서 감정 표현을 저장할 수 없는 경우다. */
  DRAWING_REFLECTION_NOT_ALLOWED(
      HttpStatus.CONFLICT, "DRAWING_409_012", "현재 상태에서는 그림 활동 감정을 저장할 수 없습니다."),
  /** 활동 완료 접수에 필요한 최종 그림이 없는 경우다. */
  FINAL_ASSET_REQUIRED(HttpStatus.CONFLICT, "DRAWING_409_013", "최종 그림이 필요합니다."),
  /** 감정 돌아보기 단계가 완료되지 않은 경우다. */
  REFLECTION_REQUIRED(HttpStatus.CONFLICT, "DRAWING_409_014", "감정 돌아보기 입력이 필요합니다."),
  /** 요청의 대화 생략 여부와 저장된 대화 상태가 일치하지 않는 경우다. */
  DRAWING_CONVERSATION_NOT_COMPLETED(
      HttpStatus.CONFLICT, "DRAWING_409_015", "대화 완료 또는 생략 상태가 올바르지 않습니다."),
  /** 활동 완료가 이미 접수됐거나 최종 완료된 경우다. */
  DRAWING_SESSION_ALREADY_COMPLETED(
      HttpStatus.CONFLICT, "DRAWING_409_016", "그림 활동 완료가 이미 접수되었습니다."),
  /** 완료 접수 저장 과정에서 동시 요청이 충돌한 경우다. */
  DRAWING_COMPLETION_CONFLICT(HttpStatus.CONFLICT, "DRAWING_409_017", "그림 활동 완료 접수 요청이 충돌했습니다."),
  /** Stroke 이벤트 순서, 좌표 또는 지표 조합이 유효하지 않은 경우다. */
  STROKE_BATCH_INVALID(HttpStatus.BAD_REQUEST, "DRAWING_400_010", "그림 과정 데이터가 올바르지 않습니다."),
  /** 압축 전 Stroke payload가 허용 크기를 초과한 경우다. */
  STROKE_BATCH_PAYLOAD_TOO_LARGE(
      HttpStatus.PAYLOAD_TOO_LARGE, "DRAWING_413_001", "그림 과정 데이터가 1 MiB 제한을 초과했습니다."),
  /** Stroke 배치 하나의 좌표 행 수가 저장 안전 상한을 초과한 경우다. */
  STROKE_BATCH_POINT_LIMIT_EXCEEDED(
      HttpStatus.PAYLOAD_TOO_LARGE, "DRAWING_413_002", "그림 과정 좌표가 20,000개 제한을 초과했습니다."),
  /** 현재 세션 상태 또는 입력 방식에서 Stroke를 저장할 수 없는 경우다. */
  STROKE_BATCH_NOT_ALLOWED(
      HttpStatus.CONFLICT, "DRAWING_409_018", "현재 상태에서는 그림 과정 데이터를 저장할 수 없습니다."),
  /** 같은 배치 순번이 다른 payload에 사용된 경우다. */
  STROKE_BATCH_CONFLICT(HttpStatus.CONFLICT, "DRAWING_409_019", "같은 순번의 다른 그림 과정 데이터가 이미 저장되었습니다."),
  /** HTP 단계 세션에 일반 활동 완료 API를 호출한 경우다. */
  HTP_AGGREGATE_COMPLETION_REQUIRED(
      HttpStatus.CONFLICT, "DRAWING_409_020", "HTP 활동은 HTP 종합 완료 API를 사용해야 합니다."),
  /** 삭제 확인 문자열이 일치하지 않는 경우다. */
  DRAWING_DELETION_CONFIRMATION_MISMATCH(
      HttpStatus.BAD_REQUEST, "DRAWING_400_011", "그림 활동 삭제 확인 값이 올바르지 않습니다."),
  /** 리포트 생성 없이 활동 완료를 요청한 경우다. */
  REPORT_REQUEST_REQUIRED(
      HttpStatus.BAD_REQUEST, "DRAWING_400_012", "활동 완료 시 관찰 리포트 생성을 요청해야 합니다."),
  /** HTP 원본 이미지 파일이 누락된 경우다. */
  DRAWING_UPLOAD_FILE_REQUIRED(
      HttpStatus.BAD_REQUEST, "DRAWING_UPLOAD_FILE_REQUIRED", "업로드할 원본 이미지가 필요합니다."),
  /** HTP 원본 이미지 Metadata가 유효하지 않은 경우다. */
  DRAWING_UPLOAD_METADATA_INVALID(
      HttpStatus.BAD_REQUEST, "DRAWING_UPLOAD_METADATA_INVALID", "이미지 업로드 정보가 올바르지 않습니다."),
  /** HTP가 아니거나 Canvas 방식 세션에 사진 업로드를 요청한 경우다. */
  DRAWING_UPLOAD_NOT_SUPPORTED(
      HttpStatus.BAD_REQUEST, "DRAWING_UPLOAD_NOT_SUPPORTED", "이 그림 활동은 사진 업로드를 지원하지 않습니다."),
  /** 세션 상태 또는 단계가 사진 업로드를 허용하지 않는 경우다. */
  DRAWING_UPLOAD_NOT_ALLOWED(
      HttpStatus.CONFLICT, "DRAWING_UPLOAD_NOT_ALLOWED", "현재 상태에서는 원본 이미지를 업로드할 수 없습니다."),
  /** 세션에 원본 이미지가 이미 저장된 경우다. */
  DRAWING_UPLOAD_ALREADY_EXISTS(
      HttpStatus.CONFLICT, "DRAWING_UPLOAD_ALREADY_EXISTS", "이 그림 단계에는 원본 이미지가 이미 존재합니다."),
  /** 같은 멱등 키가 다른 이미지 또는 Metadata에 사용된 경우다. */
  DRAWING_UPLOAD_IDEMPOTENCY_CONFLICT(
      HttpStatus.CONFLICT,
      "DRAWING_UPLOAD_IDEMPOTENCY_CONFLICT",
      "동일한 Idempotency-Key가 다른 이미지 업로드 요청에 사용되었습니다."),
  /** 원본 이미지 파일 또는 Metadata 저장에 실패한 경우다. */
  DRAWING_UPLOAD_FAILED(
      HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_UPLOAD_FAILED", "원본 이미지 저장 중 오류가 발생했습니다.");

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
