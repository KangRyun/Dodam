package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.SttVoiceAnswerMessage;
import com.ssafy.b209.conversation.exception.SttProcessingErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.SttVoiceAnswerMessageRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 외부 STT 호출과 분리된 짧은 DB 트랜잭션에서 메시지 상태를 선점·완료 처리한다.
 *
 * <p>외부 HTTP 요청을 트랜잭션 안에서 실행하지 않아 세션 잠금을 불필요하게 오래 잡지 않는다.
 */
@Service
public class SttProcessingPersistenceService {

  private final SttVoiceAnswerMessageRepository messageRepository;
  private final ConversationSessionRepository sessionRepository;

  /**
   * STT 상태 저장에 필요한 두 저장소를 연결한다.
   *
   * @param messageRepository 음성 답변 상태 조건부 갱신 저장소
   * @param sessionRepository 대화 진행 상태를 잠금 검증하는 저장소
   */
  public SttProcessingPersistenceService(
      SttVoiceAnswerMessageRepository messageRepository,
      ConversationSessionRepository sessionRepository) {
    this.messageRepository = messageRepository;
    this.sessionRepository = sessionRepository;
  }

  /**
   * PENDING 음성 답변 하나만 PROCESSING으로 원자 선점한다.
   *
   * @param conversationMessageId 288이 저장한 음성 답변 메시지 ID
   * @return 외부 호출 실행 여부와 현재 결과 snapshot
   * @throws BusinessException 메시지 형식·대화 상태가 처리 조건과 다른 경우
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public SttClaimResult claim(Long conversationMessageId) {
    SttVoiceAnswerMessage message = loadMessage(conversationMessageId);
    ConversationSession session =
        sessionRepository
            .findByIdForUpdate(message.getConversationSessionId())
            .orElseThrow(() -> new BusinessException(SttProcessingErrorCode.STT_MESSAGE_NOT_FOUND));
    if (!session.isConversing()) {
      throw new BusinessException(SttProcessingErrorCode.CONVERSATION_NOT_CONVERSING);
    }
    return switch (message.getSpeechStatus()) {
      case "PENDING" -> claimPending(message, session);
      case "PROCESSING" ->
          SttClaimResult.from(
              SttClaimResult.Action.PROCESSING, message, session.getDifficultySnapshot());
      case "SUCCESS" ->
          SttClaimResult.from(
              SttClaimResult.Action.SUCCESS, message, session.getDifficultySnapshot());
      case "FAILED" ->
          SttClaimResult.from(
              SttClaimResult.Action.FAILED, message, session.getDifficultySnapshot());
      default -> throw new BusinessException(SttProcessingErrorCode.INVALID_STT_MESSAGE);
    };
  }

  /**
   * PROCESSING으로 선점된 메시지에 성공 결과를 한 번만 반영한다.
   *
   * @param conversationMessageId 대상 메시지 ID
   * @param text schema 검증을 통과한 STT 텍스트
   * @param confidence AI 신뢰도 또는 null
   * @param needsConfirmation 보호자 확인 여부
   * @return 저장 후의 현재 상태 결과
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public SttProcessingResult completeSuccess(
      Long conversationMessageId, String text, BigDecimal confidence, boolean needsConfirmation) {
    BigDecimal databaseConfidence = normalizeConfidence(confidence);
    messageRepository.completeSuccess(
        conversationMessageId, text, databaseConfidence, needsConfirmation);
    return toResult(loadMessage(conversationMessageId));
  }

  /**
   * PROCESSING으로 선점된 메시지를 실패 상태로 끝내고 텍스트·신뢰도를 제거한다.
   *
   * @param conversationMessageId 대상 메시지 ID
   * @param needsConfirmation 보호자 확인 필요 여부
   * @return 저장 후의 현재 상태 결과
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public SttProcessingResult completeFailure(
      Long conversationMessageId, boolean needsConfirmation) {
    messageRepository.completeFailure(conversationMessageId, needsConfirmation);
    return toResult(loadMessage(conversationMessageId));
  }

  private SttClaimResult claimPending(SttVoiceAnswerMessage message, ConversationSession session) {
    if (messageRepository.claimPending(message.getId()) == 1) {
      return SttClaimResult.from(
          SttClaimResult.Action.CLAIMED, message, session.getDifficultySnapshot());
    }
    SttVoiceAnswerMessage current = loadMessage(message.getId());
    return switch (current.getSpeechStatus()) {
      case "PROCESSING" ->
          SttClaimResult.from(
              SttClaimResult.Action.PROCESSING, current, session.getDifficultySnapshot());
      case "SUCCESS" ->
          SttClaimResult.from(
              SttClaimResult.Action.SUCCESS, current, session.getDifficultySnapshot());
      case "FAILED" ->
          SttClaimResult.from(
              SttClaimResult.Action.FAILED, current, session.getDifficultySnapshot());
      default -> throw new BusinessException(SttProcessingErrorCode.INVALID_STT_MESSAGE);
    };
  }

  private SttVoiceAnswerMessage loadMessage(Long conversationMessageId) {
    SttVoiceAnswerMessage message =
        messageRepository
            .findById(conversationMessageId)
            .orElseThrow(() -> new BusinessException(SttProcessingErrorCode.STT_MESSAGE_NOT_FOUND));
    if (!"CHILD".equals(message.getSenderType())
        || !"VOICE_ANSWER".equals(message.getMessageType())
        || message.getParentMessageId() == null
        || message.getAudioStorageKey() == null
        || message.getAudioStorageKey().isBlank()) {
      throw new BusinessException(SttProcessingErrorCode.INVALID_STT_MESSAGE);
    }
    return message;
  }

  private BigDecimal normalizeConfidence(BigDecimal confidence) {
    if (confidence == null) {
      return null;
    }
    if (confidence.compareTo(BigDecimal.ZERO) < 0 || confidence.compareTo(BigDecimal.ONE) > 0) {
      throw new BusinessException(SttProcessingErrorCode.INVALID_STT_MESSAGE);
    }
    return confidence.setScale(4, RoundingMode.HALF_UP);
  }

  private SttProcessingResult toResult(SttVoiceAnswerMessage message) {
    SttProcessingResult.Status status =
        switch (message.getSpeechStatus()) {
          case "PROCESSING" -> SttProcessingResult.Status.PROCESSING;
          case "SUCCESS" -> SttProcessingResult.Status.SUCCESS;
          case "FAILED" -> SttProcessingResult.Status.FAILED;
          default -> throw new BusinessException(SttProcessingErrorCode.INVALID_STT_MESSAGE);
        };
    return new SttProcessingResult(
        message.getId(),
        status,
        message.getSttText(),
        message.getSttConfidence(),
        message.isNeedsGuardianConfirmation());
  }
}
