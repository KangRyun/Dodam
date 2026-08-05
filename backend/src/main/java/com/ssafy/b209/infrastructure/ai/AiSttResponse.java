package com.ssafy.b209.infrastructure.ai;

import java.math.BigDecimal;
import java.util.Set;

/**
 * 최신 내부 STT 계약의 200 응답 DTO이며 DB 저장 전 schema 검증을 제공한다.
 *
 * <p>{@code status}·{@code failureReason}·{@code needsConfirmation}은 정본 {@code API_명세서_최종.md}
 * §19.6이 요구하는 필드다(2026-08-05 추가). AI가 무음·저신뢰를 추측 문장 대신 실패로 알려주면 STT 원문을 저장하지 않고 FAILED로 끝낸다 — 아이가
 * 하지 않은 말이 대화 기록과 리포트 근거로 남는 것을 막는다.
 *
 * <p>세 필드는 구 AI 배포에서 오지 않을 수 있어 모두 nullable로 받는다. 없으면 {@code SUCCESS}로 간주하고, 대신 {@link #text()}의 공백
 * 여부로 무음을 판정한다({@link #failed()}).
 *
 * @param text 인식된 STT 원문이며 실패 시 빈 문자열
 * @param confidence whisper-1이 제공하지 않아 항상 {@code null}인 신뢰도
 * @param modelName AI 모델 관측값이며 DB에는 저장하지 않음
 * @param processingTimeMs AI 처리 시간 관측값이며 DB에는 저장하지 않음
 * @param status {@code SUCCESS} 또는 {@code FAILED}이며 구 AI 응답에서는 {@code null}
 * @param failureReason {@code NO_SPEECH}·{@code LOW_CONFIDENCE}·{@code UNSUPPORTED_AUDIO}·{@code
 *     TIMEOUT} 중 하나이거나 {@code null}
 * @param needsConfirmation 텍스트를 확정하지 않고 보호자 확인을 요구해야 하는지 여부
 */
public record AiSttResponse(
    String text,
    BigDecimal confidence,
    String modelName,
    Long processingTimeMs,
    String status,
    String failureReason,
    Boolean needsConfirmation) {

  private static final String STATUS_SUCCESS = "SUCCESS";
  private static final String STATUS_FAILED = "FAILED";

  /** 정본 §19.6이 정의한 실패 사유. 이 목록 밖의 값은 계약 위반으로 본다. */
  private static final Set<String> FAILURE_REASONS =
      Set.of("NO_SPEECH", "LOW_CONFIDENCE", "UNSUPPORTED_AUDIO", "TIMEOUT");

  /** 무음을 판정할 수 없는 구 AI 응답에서 쓰는 대체 사유. */
  public static final String REASON_BLANK_TEXT = "NO_SPEECH";

  /**
   * 상태 필드가 없던 구 AI 응답 형태를 만든다.
   *
   * <p>생성자를 하나로 유지하려고 정적 팩토리로 둔다 — record에 생성자를 더 두면 Jackson이 어느 것을 creator로 쓸지 모호해지고, 그 실패는 런타임
   * 역직렬화에서만 드러난다.
   *
   * @param text 인식된 STT 원문
   * @param modelName AI 모델 관측값
   * @param processingTimeMs AI 처리 시간 관측값
   * @return 상태·사유·확인 필드가 비어 있는 응답
   */
  public static AiSttResponse legacy(String text, String modelName, Long processingTimeMs) {
    return new AiSttResponse(text, null, modelName, processingTimeMs, null, null, null);
  }

  /**
   * AI 응답이 최신 STT DTO의 필수값·null confidence 규칙을 지키는지 확인한다.
   *
   * <p>상태 어휘도 함께 본다. 모르는 {@code status}를 성공으로 넘기면 AI가 실패라고 말한 결과가 아이 답변으로 저장될 수 있어, 판정 불가는 schema
   * 오류로 떨어뜨린다(fail-closed).
   *
   * @throws AiSttClientException 필수 필드·confidence·처리 시간·상태 어휘가 계약과 다른 경우
   */
  public void validateContract() {
    if (text == null
        || confidence != null
        || modelName == null
        || modelName.isBlank()
        || processingTimeMs == null
        || processingTimeMs < 0) {
      throw schemaError();
    }
    if (status != null && !STATUS_SUCCESS.equals(status) && !STATUS_FAILED.equals(status)) {
      throw schemaError();
    }
    if (failureReason != null && !FAILURE_REASONS.contains(failureReason)) {
      throw schemaError();
    }
    if (STATUS_FAILED.equals(status) && failureReason == null) {
      throw schemaError();
    }
  }

  /**
   * 저장하지 않고 FAILED로 끝내야 하는 응답인지 판정한다.
   *
   * <p>두 경로가 있다. AI가 {@code status=FAILED}를 준 경우와, 상태 필드가 없는 구 AI가 빈 텍스트를 준 경우다. 후자를 성공으로 저장하면 빈
   * 답변이 아이 발화로 기록되고 다음 질문의 근거가 된다.
   *
   * @return 실패로 처리해야 하면 {@code true}
   */
  public boolean failed() {
    return STATUS_FAILED.equals(status) || text == null || text.isBlank();
  }

  /**
   * 로그에 남길 실패 사유를 고른다. STT 원문은 포함하지 않는다.
   *
   * @return AI가 준 사유 또는 빈 텍스트를 뜻하는 대체 사유
   */
  public String resolvedFailureReason() {
    return failureReason != null ? failureReason : REASON_BLANK_TEXT;
  }

  /**
   * 보호자 확인 필요 여부를 계약 기본값과 함께 해석한다.
   *
   * @return AI가 지정한 값이며 없으면 {@code false}
   */
  public boolean needsConfirmationOrDefault() {
    return Boolean.TRUE.equals(needsConfirmation);
  }

  private AiSttClientException schemaError() {
    return new AiSttClientException(AiSttClientException.Type.RESPONSE_SCHEMA_INVALID);
  }
}
