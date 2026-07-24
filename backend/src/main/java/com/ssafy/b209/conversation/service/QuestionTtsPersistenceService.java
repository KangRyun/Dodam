package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.QuestionTtsMessage;
import com.ssafy.b209.conversation.exception.ConversationMessageStatusErrorCode;
import com.ssafy.b209.conversation.exception.QuestionTtsErrorCode;
import com.ssafy.b209.conversation.repository.QuestionTtsMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 외부 AI 합성 호출과 분리된 짧은 DB 트랜잭션에서 질문 음성 상태를 선점·완료 처리한다.
 *
 * <p>외부 HTTP 요청과 파일 저장을 트랜잭션 안에서 실행하지 않아 세션 잠금을 불필요하게 오래 잡지 않는다.
 */
@Service
public class QuestionTtsPersistenceService {

  private final QuestionTtsMessageRepository messageRepository;

  /**
   * 질문 TTS 상태 저장소를 연결한다.
   *
   * @param messageRepository 질문 음성 상태 조건부 갱신 저장소
   */
  public QuestionTtsPersistenceService(QuestionTtsMessageRepository messageRepository) {
    this.messageRepository = messageRepository;
  }

  /**
   * 성공 음성이 없는 AI 질문 하나만 PROCESSING으로 원자 선점한다.
   *
   * @param messageId TTS 대상 AI 질문 메시지 ID
   * @return 캐시 히트·선점·진행 중 여부와 자막·저장 key snapshot
   * @throws BusinessException 메시지가 없거나(404) 음성을 생성할 AI 질문이 아닌 경우(400)
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public QuestionTtsClaimResult claim(Long messageId) {
    QuestionTtsMessage message = loadAiQuestion(messageId);
    if (hasCachedAudio(message)) {
      return QuestionTtsClaimResult.of(QuestionTtsClaimResult.Action.CACHE_HIT, message);
    }
    if ("PROCESSING".equals(message.getSpeechStatus())) {
      return QuestionTtsClaimResult.of(QuestionTtsClaimResult.Action.IN_PROGRESS, message);
    }
    if (messageRepository.claimForSynthesis(messageId) == 1) {
      return QuestionTtsClaimResult.of(QuestionTtsClaimResult.Action.CLAIMED, message);
    }
    QuestionTtsMessage current = loadAiQuestion(messageId);
    if (hasCachedAudio(current)) {
      return QuestionTtsClaimResult.of(QuestionTtsClaimResult.Action.CACHE_HIT, current);
    }
    return QuestionTtsClaimResult.of(QuestionTtsClaimResult.Action.IN_PROGRESS, current);
  }

  /**
   * PROCESSING으로 선점된 질문에 성공 음성 결과를 한 번만 반영한다.
   *
   * @param messageId 대상 메시지 ID
   * @param storageKey 승격된 음성의 Root-relative 저장 key
   * @param audioUrl 재생 프록시 상대 경로
   * @return 성공 갱신이 실제로 반영되면 {@code true}
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public boolean completeSuccess(Long messageId, String storageKey, String audioUrl) {
    return messageRepository.completeSuccess(messageId, storageKey, audioUrl) == 1;
  }

  /**
   * PROCESSING으로 선점된 질문을 실패 상태로 끝낸다.
   *
   * @param messageId 대상 메시지 ID
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void markFailed(Long messageId) {
    messageRepository.markFailed(messageId);
  }

  private boolean hasCachedAudio(QuestionTtsMessage message) {
    return "SUCCESS".equals(message.getSpeechStatus())
        && message.getAudioStorageKey() != null
        && !message.getAudioStorageKey().isBlank();
  }

  private QuestionTtsMessage loadAiQuestion(Long messageId) {
    QuestionTtsMessage message =
        messageRepository
            .findById(messageId)
            .orElseThrow(
                () ->
                    new BusinessException(
                        ConversationMessageStatusErrorCode.CONVERSATION_MESSAGE_NOT_FOUND));
    if (!message.isAiQuestion() || message.getRawText() == null || message.getRawText().isBlank()) {
      throw new BusinessException(QuestionTtsErrorCode.TTS_NOT_APPLICABLE);
    }
    return message;
  }
}
