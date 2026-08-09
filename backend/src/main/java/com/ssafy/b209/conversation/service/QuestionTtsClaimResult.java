package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.QuestionTtsMessage;

/**
 * 질문 TTS 음성 상태 선점 결과 snapshot이다.
 *
 * <p>외부 AI 호출을 트랜잭션 밖에서 수행하기 위해, 짧은 선점 트랜잭션이 관찰한 상태와 자막·저장 key만 담아 반환한다.
 *
 * @param action 선점 이후 오케스트레이터가 수행할 동작
 * @param messageId 대상 질문 메시지 ID
 * @param subtitle 자막으로 사용할 질문 원문
 * @param audioStorageKey 캐시 히트일 때의 기존 저장 key 또는 {@code null}
 */
public record QuestionTtsClaimResult(
    Action action, Long messageId, String subtitle, String audioStorageKey) {

  /** 선점 결과에 따른 후속 동작 유형이다. */
  public enum Action {
    /** 이미 성공 음성이 있어 AI 호출 없이 기존 결과를 반환한다. */
    CACHE_HIT,
    /** 이 요청이 PROCESSING을 선점해 새로 합성한다. */
    CLAIMED,
    /** 다른 요청이 합성 중이라 이번 요청은 진행하지 않는다. */
    IN_PROGRESS
  }

  static QuestionTtsClaimResult of(Action action, QuestionTtsMessage message) {
    return new QuestionTtsClaimResult(
        action, message.getId(), message.getRawText(), message.getAudioStorageKey());
  }
}
