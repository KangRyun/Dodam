package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.SttVoiceAnswerMessage;
import java.math.BigDecimal;

/**
 * 289 상태 선점 결과와 외부 STT 호출 여부를 전달하는 내부 값 객체다.
 *
 * @param action STT 호출 선점 여부 또는 기존 종료 상태
 * @param messageId 음성 답변 메시지 ID
 * @param audioStorageKey 내부 파일 읽기에만 쓰는 Root-relative key
 * @param difficultySnapshot 개인정보를 포함하지 않는 연령대 대체 계약값
 * @param speechStatus DB의 현재 음성 처리 상태
 * @param sttText 이미 성공한 경우에만 존재하는 기존 원문
 * @param sttConfidence 이미 성공한 경우의 기존 신뢰도
 * @param needsGuardianConfirmation 기존 보호자 확인 필요 여부
 */
public record SttClaimResult(
    Action action,
    Long messageId,
    String audioStorageKey,
    String difficultySnapshot,
    String speechStatus,
    String sttText,
    BigDecimal sttConfidence,
    boolean needsGuardianConfirmation) {

  /** STT 외부 호출을 실행할지와 기존 상태를 구분한다. */
  public enum Action {
    CLAIMED,
    PROCESSING,
    SUCCESS,
    FAILED
  }

  /** 영속 Entity의 현재 결과를 외부 호출 없는 상태 결과로 바꾼다. */
  static SttClaimResult from(
      Action action, SttVoiceAnswerMessage message, String difficultySnapshot) {
    return new SttClaimResult(
        action,
        message.getId(),
        message.getAudioStorageKey(),
        difficultySnapshot,
        message.getSpeechStatus(),
        message.getSttText(),
        message.getSttConfidence(),
        message.isNeedsGuardianConfirmation());
  }
}
