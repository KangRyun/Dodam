package com.ssafy.b209.conversation.service;

import java.math.BigDecimal;

/**
 * 289 처리 호출자가 재생하거나 polling에 사용할 비식별 STT 상태 결과다.
 *
 * @param conversationMessageId 처리한 음성 답변 메시지 ID
 * @param status 처리 완료 또는 진행 중 상태
 * @param text 성공 상태에만 존재하는 STT 원문
 * @param confidence 성공 상태에만 존재하는 신뢰도
 * @param needsGuardianConfirmation 보호자 확인 필요 여부
 */
public record SttProcessingResult(
    Long conversationMessageId,
    Status status,
    String text,
    BigDecimal confidence,
    boolean needsGuardianConfirmation) {

  /** DB speech_status를 호출 결과로 제한해 표현한 값이다. */
  public enum Status {
    PROCESSING,
    SUCCESS,
    FAILED
  }
}
