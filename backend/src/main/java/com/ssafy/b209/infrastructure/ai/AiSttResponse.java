package com.ssafy.b209.infrastructure.ai;

import java.math.BigDecimal;

/**
 * 최신 내부 STT 계약의 200 응답 DTO이며 DB 저장 전 schema 검증을 제공한다.
 *
 * @param text 인식된 STT 원문
 * @param confidence whisper-1이 제공하지 않아 항상 {@code null}인 신뢰도
 * @param modelName AI 모델 관측값이며 DB에는 저장하지 않음
 * @param processingTimeMs AI 처리 시간 관측값이며 DB에는 저장하지 않음
 */
public record AiSttResponse(
    String text, BigDecimal confidence, String modelName, Long processingTimeMs) {

  /**
   * AI 응답이 최신 STT 성공 DTO의 필수값·null confidence 규칙을 지키는지 확인한다.
   *
   * @throws AiSttClientException 필수 필드·confidence·처리 시간이 계약과 다른 경우
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
  }

  private AiSttClientException schemaError() {
    return new AiSttClientException(AiSttClientException.Type.RESPONSE_SCHEMA_INVALID);
  }
}
