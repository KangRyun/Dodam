package com.ssafy.b209.drawing.exception;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.EnumMap;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class DrawingErrorCodeTest {

  @Test
  void exposesTheExactDrawingErrorCodeContract() {
    Map<DrawingErrorCode, ErrorContract> original =
        Map.of(
            DrawingErrorCode.CHILD_NOT_FOUND,
            new ErrorContract(HttpStatus.NOT_FOUND, "DRAWING_404_001", "아동 정보를 찾을 수 없습니다."),
            DrawingErrorCode.DRAWING_TYPE_NOT_FOUND,
            new ErrorContract(HttpStatus.NOT_FOUND, "DRAWING_404_002", "그림 활동 유형을 찾을 수 없습니다."),
            DrawingErrorCode.DRAWING_TYPE_NOT_AVAILABLE,
            new ErrorContract(
                HttpStatus.BAD_REQUEST, "DRAWING_400_001", "현재 선택할 수 없는 그림 활동 유형입니다."),
            DrawingErrorCode.INVALID_CANVAS_CONFIGURATION,
            new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_002", "캔버스 설정이 올바르지 않습니다."),
            DrawingErrorCode.IDEMPOTENCY_KEY_REQUIRED,
            new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_003", "Idempotency-Key가 필요합니다."),
            DrawingErrorCode.IDEMPOTENCY_KEY_INVALID,
            new ErrorContract(
                HttpStatus.BAD_REQUEST, "DRAWING_400_004", "Idempotency-Key 형식이 올바르지 않습니다."),
            DrawingErrorCode.ACTIVE_DRAWING_SESSION_EXISTS,
            new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_001", "진행 중인 그림 활동이 이미 존재합니다."),
            DrawingErrorCode.IDEMPOTENCY_KEY_CONFLICT,
            new ErrorContract(
                HttpStatus.CONFLICT, "DRAWING_409_002", "동일한 Idempotency-Key가 다른 요청에 사용되었습니다."),
            DrawingErrorCode.DRAWING_SESSION_CREATION_CONFLICT,
            new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_003", "그림 활동 생성 요청이 충돌했습니다."));

    Map<DrawingErrorCode, ErrorContract> expected = new EnumMap<>(DrawingErrorCode.class);
    expected.putAll(original);
    expected.put(
        DrawingErrorCode.DRAWING_SESSION_NOT_FOUND,
        new ErrorContract(HttpStatus.NOT_FOUND, "DRAWING_404_003", "그림 활동을 찾을 수 없습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_SESSION_NOT_UPLOADABLE,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_004", "현재 상태에서는 그림을 업로드할 수 없습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_SNAPSHOT_FILE_REQUIRED,
        new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_005", "업로드할 그림 파일이 필요합니다."));
    expected.put(
        DrawingErrorCode.DRAWING_SNAPSHOT_METADATA_INVALID,
        new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_006", "그림 스냅샷 정보가 올바르지 않습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_SNAPSHOT_SEQUENCE_CONFLICT,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_005", "같은 순서의 그림 스냅샷이 이미 존재합니다."));
    expected.put(
        DrawingErrorCode.DRAWING_FINAL_SNAPSHOT_EXISTS,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_006", "최종 그림 스냅샷이 이미 존재합니다."));
    expected.put(
        DrawingErrorCode.DRAWING_SNAPSHOT_STORAGE_FAILED,
        new ErrorContract(
            HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_001", "그림 스냅샷 저장 중 오류가 발생했습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_SNAPSHOT_CREATION_CONFLICT,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_007", "그림 스냅샷 저장 요청이 충돌했습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_DRAFT_NOT_FOUND,
        new ErrorContract(HttpStatus.NOT_FOUND, "DRAWING_404_004", "저장된 그림 초안이 없습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_DRAFT_NOT_ALLOWED,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_008", "현재 상태에서는 그림 초안을 저장할 수 없습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_DRAFT_VERSION_CONFLICT,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_009", "같은 순서의 그림 초안이 이미 저장되어 있습니다."));
    expected.put(
        DrawingErrorCode.STALE_DRAWING_DRAFT_VERSION,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_010", "더 최근의 그림 초안이 이미 저장되어 있습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_DRAFT_SAVE_CONFLICT,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_011", "그림 초안 저장 요청이 충돌했습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_DRAFT_STORAGE_FAILED,
        new ErrorContract(
            HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_002", "그림 초안 저장 중 오류가 발생했습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_DRAFT_FILE_REQUIRED,
        new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_007", "초안 미리보기 파일이 필요합니다."));
    expected.put(
        DrawingErrorCode.DRAWING_DRAFT_METADATA_INVALID,
        new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_008", "그림 초안 정보가 올바르지 않습니다."));
    expected.put(
        DrawingErrorCode.ACTIVE_DRAWING_SESSION_NOT_FOUND,
        new ErrorContract(HttpStatus.NOT_FOUND, "DRAWING_404_005", "진행 중인 그림 활동이 없습니다."));
    expected.put(
        DrawingErrorCode.MULTIPLE_ACTIVE_DRAWING_SESSIONS,
        new ErrorContract(
            HttpStatus.INTERNAL_SERVER_ERROR, "DRAWING_500_003", "진행 중인 그림 활동 데이터가 중복되었습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_REFLECTION_INVALID,
        new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_009", "그림 활동 감정 정보가 올바르지 않습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_REFLECTION_NOT_ALLOWED,
        new ErrorContract(
            HttpStatus.CONFLICT, "DRAWING_409_012", "현재 상태에서는 그림 활동 감정을 저장할 수 없습니다."));
    expected.put(
        DrawingErrorCode.FINAL_ASSET_REQUIRED,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_013", "최종 그림이 필요합니다."));
    expected.put(
        DrawingErrorCode.REFLECTION_REQUIRED,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_014", "감정 돌아보기 입력이 필요합니다."));
    expected.put(
        DrawingErrorCode.DRAWING_CONVERSATION_NOT_COMPLETED,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_015", "대화 완료 또는 생략 상태가 올바르지 않습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_SESSION_ALREADY_COMPLETED,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_016", "그림 활동 완료가 이미 접수되었습니다."));
    expected.put(
        DrawingErrorCode.DRAWING_COMPLETION_CONFLICT,
        new ErrorContract(HttpStatus.CONFLICT, "DRAWING_409_017", "그림 활동 완료 접수 요청이 충돌했습니다."));
    expected.put(
        DrawingErrorCode.STROKE_BATCH_INVALID,
        new ErrorContract(HttpStatus.BAD_REQUEST, "DRAWING_400_010", "그림 과정 데이터가 올바르지 않습니다."));
    expected.put(
        DrawingErrorCode.STROKE_BATCH_PAYLOAD_TOO_LARGE,
        new ErrorContract(
            HttpStatus.PAYLOAD_TOO_LARGE, "DRAWING_413_001", "그림 과정 데이터 크기가 제한을 초과했습니다."));
    expected.put(
        DrawingErrorCode.STROKE_BATCH_NOT_ALLOWED,
        new ErrorContract(
            HttpStatus.CONFLICT, "DRAWING_409_018", "현재 상태에서는 그림 과정 데이터를 저장할 수 없습니다."));
    expected.put(
        DrawingErrorCode.STROKE_BATCH_CONFLICT,
        new ErrorContract(
            HttpStatus.CONFLICT, "DRAWING_409_019", "같은 순번의 다른 그림 과정 데이터가 이미 저장되었습니다."));

    assertThat(DrawingErrorCode.values()).containsExactlyInAnyOrderElementsOf(expected.keySet());
    expected.forEach(
        (errorCode, contract) -> {
          assertThat(errorCode.getHttpStatus()).isEqualTo(contract.httpStatus());
          assertThat(errorCode.getCode()).isEqualTo(contract.code());
          assertThat(errorCode.getMessage()).isEqualTo(contract.message());
        });
  }

  private record ErrorContract(HttpStatus httpStatus, String code, String message) {}
}
