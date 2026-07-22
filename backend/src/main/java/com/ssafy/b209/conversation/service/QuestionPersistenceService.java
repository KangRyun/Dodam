package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationMessageOption;
import com.ssafy.b209.conversation.domain.ConversationMessageTarget;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.GeneratedQuestion;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.repository.ConversationMessageOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageTargetRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.List;
import java.util.stream.IntStream;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** AI 호출 이후의 짧은 질문 저장 트랜잭션을 분리한다. */
@Service
class QuestionPersistenceService {

  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationMessageRepository conversationMessageRepository;
  private final ConversationMessageOptionRepository conversationMessageOptionRepository;
  private final ConversationMessageTargetRepository conversationMessageTargetRepository;

  QuestionPersistenceService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationMessageRepository conversationMessageRepository,
      ConversationMessageOptionRepository conversationMessageOptionRepository,
      ConversationMessageTargetRepository conversationMessageTargetRepository) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.conversationMessageRepository = conversationMessageRepository;
    this.conversationMessageOptionRepository = conversationMessageOptionRepository;
    this.conversationMessageTargetRepository = conversationMessageTargetRepository;
  }

  @Transactional
  public GeneratedQuestion save(Long conversationId, QuestionCandidate candidate) {
    ConversationSession session =
        conversationSessionRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    if (!session.canAskQuestion()) {
      throw new BusinessException(ConversationErrorCode.QUESTION_LIMIT_REACHED);
    }

    int nextSequence =
        conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(conversationId)
            + 1;
    try {
      ConversationMessage message =
          conversationMessageRepository.saveAndFlush(
              ConversationMessage.aiQuestion(
                  conversationId,
                  candidate.questionTemplateId(),
                  nextSequence,
                  candidate.questionText()));
      saveOptionSnapshots(message.getId(), candidate.options());
      saveTargetSnapshot(message.getId(), candidate.targetObject());
      session.increaseQuestionCount();
      return new GeneratedQuestion(message.getId(), message.getRawText(), candidate.fallbackUsed());
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(ConversationErrorCode.QUESTION_STORAGE_CONFLICT, exception);
    }
  }

  private void saveOptionSnapshots(Long messageId, List<QuestionOption> options) {
    if (options == null || options.isEmpty()) {
      return;
    }
    conversationMessageOptionRepository.saveAll(
        IntStream.range(0, options.size())
            .mapToObj(
                index ->
                    ConversationMessageOption.snapshot(
                        messageId, options.get(index), (short) index))
            .toList());
  }

  private void saveTargetSnapshot(Long messageId, DetectedObject targetObject) {
    if (targetObject != null) {
      conversationMessageTargetRepository.save(
          ConversationMessageTarget.snapshot(messageId, targetObject));
    }
  }
}
