package com.ssafy.b209.drawing.exception;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class DrawingErrorCodeTest {

  @Test
  void exposesTheExactDrawingErrorCodeContract() {
    Map<DrawingErrorCode, ErrorContract> expected =
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
