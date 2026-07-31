package com.ssafy.b209.drawing.htp.exception;

import com.ssafy.b209.global.response.ErrorCode;
import org.springframework.http.HttpStatus;

/** HTP 묶음과 단계 전이 API가 공개하는 안전한 오류 코드를 정의한다. */
public enum HtpErrorCode implements ErrorCode {
  /** HTP 활동을 찾을 수 없거나 접근할 수 없는 경우다. */
  HTP_ASSESSMENT_NOT_FOUND(HttpStatus.NOT_FOUND, "HTP_404_001", "HTP 활동을 찾을 수 없습니다."),
  /** 활성화된 HTP 그림 유형이 준비되지 않은 경우다. */
  HTP_TYPE_NOT_AVAILABLE(HttpStatus.CONFLICT, "HTP_409_001", "현재 HTP 활동을 시작할 수 없습니다."),
  /** 일반 그림 활동 또는 다른 HTP 활동이 진행 중인 경우다. */
  ACTIVE_ACTIVITY_EXISTS(HttpStatus.CONFLICT, "HTP_409_002", "진행 중인 그림 활동이 이미 존재합니다."),
  /** 현재 그림의 분석과 대화가 끝나지 않은 경우다. */
  CURRENT_STEP_NOT_COMPLETED(HttpStatus.CONFLICT, "HTP_409_003", "현재 HTP 그림 단계가 아직 완료되지 않았습니다."),
  /** HTP 활동이 만료됐거나 이미 종료되어 상태를 변경할 수 없는 경우다. */
  HTP_TRANSITION_NOT_ALLOWED(HttpStatus.CONFLICT, "HTP_409_004", "현재 상태에서는 HTP 단계를 변경할 수 없습니다."),
  /** 같은 멱등 키가 다른 HTP 시작 요청에 사용된 경우다. */
  IDEMPOTENCY_KEY_CONFLICT(
      HttpStatus.CONFLICT, "HTP_409_005", "동일한 Idempotency-Key가 다른 요청에 사용되었습니다."),
  /** HTP 상태 변경 요청에 멱등 키가 없는 경우다. */
  IDEMPOTENCY_KEY_REQUIRED(HttpStatus.BAD_REQUEST, "HTP_400_001", "Idempotency-Key가 필요합니다."),
  /** HTP 상태 변경 요청의 멱등 키 형식이 잘못된 경우다. */
  IDEMPOTENCY_KEY_INVALID(HttpStatus.BAD_REQUEST, "HTP_400_002", "Idempotency-Key 형식이 올바르지 않습니다."),
  /**
   * HOUSE, TREE, PERSON 세 단계 구성 자체가 완성되지 않은 경우다.
   *
   * <p>단계 수가 3이 아니거나 주제 순서가 HOUSE, TREE, PERSON이 아닐 때만 사용한다. 개별 단계의 그림·최종 이미지·대화 미완료는 {@link
   * #HTP_STEP_DRAWING_NOT_COMPLETED}, {@link #HTP_FINAL_IMAGE_REQUIRED}, {@link
   * #HTP_CONVERSATION_NOT_COMPLETED}로 구분해 응답한다.
   */
  HTP_RESULTS_NOT_READY(HttpStatus.CONFLICT, "HTP_409_006", "HTP 세 단계 구성이 완료되지 않았습니다."),
  /** 다른 완료 요청이 처리 중이거나 이미 완료된 HTP 활동인 경우다. */
  HTP_COMPLETION_CONFLICT(HttpStatus.CONFLICT, "HTP_409_007", "HTP 종합 완료 요청을 처리할 수 없습니다."),
  /** 세 단계 중 그림 활동 세션이 완료되지 않은 단계가 있는 경우다. */
  HTP_STEP_DRAWING_NOT_COMPLETED(
      HttpStatus.CONFLICT, "HTP_409_008", "HTP 세 단계의 그림 활동을 모두 마쳐야 합니다."),
  /** 세 단계 중 최종 그림이 저장되지 않은 단계가 있는 경우다. */
  HTP_FINAL_IMAGE_REQUIRED(HttpStatus.CONFLICT, "HTP_409_009", "HTP 세 단계의 최종 그림이 모두 필요합니다."),
  /** 세 단계 중 대화가 완료되지 않은 단계가 있는 경우다. */
  HTP_CONVERSATION_NOT_COMPLETED(HttpStatus.CONFLICT, "HTP_409_010", "HTP 세 단계의 대화를 모두 마쳐야 합니다."),
  /** 현재 주제의 감정 선택을 저장하지 않고 다음 단계 전이를 요청한 경우다. */
  HTP_REFLECTION_REQUIRED(
      HttpStatus.CONFLICT, "HTP_409_011", "현재 HTP 그림의 감정을 선택한 후 다음 단계로 이동해 주세요.");

  private final HttpStatus httpStatus;
  private final String code;
  private final String message;

  HtpErrorCode(HttpStatus httpStatus, String code, String message) {
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
