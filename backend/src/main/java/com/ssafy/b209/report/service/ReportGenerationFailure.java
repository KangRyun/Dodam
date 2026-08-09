package com.ssafy.b209.report.service;

import com.ssafy.b209.infrastructure.ai.observation.AiObservationClientException;
import com.ssafy.b209.report.domain.ReportStatus;
import java.util.Objects;

/**
 * 리포트 생성 실패 한 건을 재시도 판단과 함께 담는다 (S15P11B209 P0-2).
 *
 * <p><strong>여기에는 개인정보·음성 원문·시크릿이 들어가지 않는다.</strong> {@code code}는 분류 이름이고 {@code message}는 미리 정해 둔
 * 안전한 문구이며, {@code correlationId}는 UUID다. 이 레코드의 모든 필드는 그대로 로그에 나가도 된다 — 그렇게 만든 자리다.
 *
 * @param stage 실패한 단계
 * @param code 원문을 포함하지 않는 실패 분류 코드
 * @param message 외부에 노출해도 되는 안전한 실패 메시지
 * @param retryable 그대로 다시 시도해 볼 값어치가 있으면 {@code true}
 * @param correlationId 요청과 로그를 잇는 식별자
 */
public record ReportGenerationFailure(
    ReportFailureStage stage,
    String code,
    String message,
    boolean retryable,
    String correlationId) {

  /** 방어적으로 필수값을 확인한다. */
  public ReportGenerationFailure {
    Objects.requireNonNull(stage, "stage must not be null");
    Objects.requireNonNull(code, "code must not be null");
  }

  /**
   * AI 호출 실패를 유형에 따라 분류한다.
   *
   * <p>타임아웃과 5xx는 상대편이 잠깐 흔들린 것이라 다시 하면 될 수 있다. 반면 {@code INVALID_RESPONSE}는 같은 입력에 같은 응답이 오므로 몇 번을
   * 더 불러도 같은 자리에서 멈춘다. {@code REQUEST_FAILED}는 요청 자체가 거절된 것이라 마찬가지다.
   *
   * @param type AI Client가 분류한 실패 유형
   * @param message 외부에 노출해도 되는 안전한 실패 메시지
   * @param correlationId 요청과 로그를 잇는 식별자
   * @return 재시도 판단이 담긴 실패
   */
  public static ReportGenerationFailure ofAiCall(
      AiObservationClientException.Type type, String message, String correlationId) {
    boolean retryable =
        type == AiObservationClientException.Type.TIMEOUT
            || type == AiObservationClientException.Type.SERVER_ERROR;
    return new ReportGenerationFailure(
        ReportFailureStage.AI_CALL, type.name(), message, retryable, correlationId);
  }

  /**
   * 응답 계약 위반을 최종 실패로 분류한다.
   *
   * @param code 검증이 지목한 사유
   * @param message 외부에 노출해도 되는 안전한 실패 메시지
   * @param correlationId 요청과 로그를 잇는 식별자
   * @return 재시도하지 않는 실패
   */
  public static ReportGenerationFailure ofInvalidResponse(
      String code, String message, String correlationId) {
    return new ReportGenerationFailure(
        ReportFailureStage.RESPONSE_VALIDATION, code, message, false, correlationId);
  }

  /**
   * 저장 실패를 분류한다.
   *
   * <p>저장은 기본적으로 재시도 대상이다. 여기까지 왔다는 것은 AI가 쓸 만한 결과를 이미 돌려줬다는 뜻이고, 그 결과를 못 넣은 이유는 대개 잠금 경합이나 순간적인 DB
   * 문제다. 다만 {@code *_CONFLICT}는 이미 누군가 저장했다는 신호라 다시 해도 같은 자리에서 막힌다.
   *
   * @param code 원문을 포함하지 않는 실패 분류 코드
   * @param message 외부에 노출해도 되는 안전한 실패 메시지
   * @param correlationId 요청과 로그를 잇는 식별자
   * @return 재시도 판단이 담긴 실패
   */
  public static ReportGenerationFailure ofPersistence(
      String code, String message, String correlationId) {
    boolean retryable = code == null || !code.endsWith("_CONFLICT");
    return new ReportGenerationFailure(
        ReportFailureStage.PERSISTENCE, code, message, retryable, correlationId);
  }

  /**
   * @return 이 실패를 기록할 리포트 상태
   */
  public ReportStatus reportStatus() {
    return retryable ? ReportStatus.FAILED_RETRYABLE : ReportStatus.FAILED_FINAL;
  }
}
