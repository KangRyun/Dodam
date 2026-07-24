package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationMessageOption;
import com.ssafy.b209.conversation.domain.ConversationMessageTarget;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.GeneratedQuestion;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
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

/**
 * AI 호출 이후 질문·선택지·대상 Snapshot과 세션 질문 수를 하나의 짧은 트랜잭션으로 저장한다.
 *
 * <p>대화 세션의 비관 잠금 아래 상태·상한·부모 답변을 재검증하고, 세션별 순번과 정규화 Snapshot을 저장한 뒤 질문 수를 증가시킨다.
 */
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

  /**
   * 검증된 질문 후보를 현재 대화 세션에 원자적으로 저장한다.
   *
   * @param conversationId 잠글 대화 세션 식별자
   * @param candidate AI 또는 폴백으로 확정한 질문·선택지·대상·부모 답변 후보
   * @return 저장된 메시지 식별자, 순번, 정규화 Snapshot을 담은 결과
   * @throws BusinessException 세션 상태·상한·부모 답변이 유효하지 않거나 순번 UNIQUE 충돌이 발생한 경우
   */
  @Transactional
  public GeneratedQuestion save(Long conversationId, QuestionCandidate candidate) {
    ConversationSession session =
        conversationSessionRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    if (session.isCompleted()) {
      throw new BusinessException(ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);
    }
    if (!session.isConversing()) {
      throw new BusinessException(ConversationStartErrorCode.INVALID_STATE_TRANSITION);
    }
    if (!session.canAskQuestion()) {
      throw new BusinessException(ConversationErrorCode.QUESTION_LIMIT_REACHED);
    }
    validateParentMessage(conversationId, candidate.parentMessageId());
    rejectDuplicateFollowUpQuestion(conversationId, candidate.parentMessageId());

    int nextSequence =
        conversationMessageRepository.findMaxMessageSequenceByConversationSessionId(conversationId)
            + 1;
    try {
      ConversationMessage message =
          conversationMessageRepository.saveAndFlush(
              ConversationMessage.aiQuestion(
                  conversationId,
                  candidate.parentMessageId(),
                  candidate.questionTemplateId(),
                  nextSequence,
                  candidate.questionText()));
      saveOptionSnapshots(message.getId(), candidate.options());
      saveTargetSnapshot(message.getId(), candidate.targetObject());
      session.increaseQuestionCount();
      return new GeneratedQuestion(
          message.getId(),
          message.getRawText(),
          candidate.fallbackUsed(),
          nextSequence,
          candidate.options() == null ? List.of() : List.copyOf(candidate.options()),
          candidate.targetObject());
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(ConversationErrorCode.QUESTION_STORAGE_CONFLICT, exception);
    }
  }

  /**
   * 같은 이전 답변을 부모로 이어받은 질문이 이미 저장돼 있으면 중복 생성으로 판단해 거부한다.
   *
   * <p>세션 비관 잠금 아래에서 순번 계산·저장 직전에 수행하는 도메인 턴교대 가드다. 서로 다른 멱등성 키로 next-question이 두 번 호출되면서 둘 다 같은 아동
   * 답변을 참조하면, 각 요청이 서로 다른 순번을 얻어 답변 1건에 질문이 2건 이어지는 갭이 생긴다. 세션별 순번 UNIQUE는 같은 순번만 막으므로 이 갭을 여기서
   * 차단한다. 부모 답변이 없는 최초 질문({@code parentMessageId == null})은 정상 흐름이므로 막지 않는다.
   *
   * @param conversationId 잠근 대화 세션 식별자
   * @param parentMessageId 이어받은 이전 답변 메시지 식별자 또는 최초 질문의 {@code null}
   * @throws BusinessException 같은 부모 답변을 이어받은 질문이 이미 있는 경우
   */
  private void rejectDuplicateFollowUpQuestion(Long conversationId, Long parentMessageId) {
    if (parentMessageId == null) {
      return;
    }
    if (conversationMessageRepository.existsQuestionByParentMessageId(
        conversationId, parentMessageId)) {
      throw new BusinessException(ConversationErrorCode.QUESTION_STORAGE_CONFLICT);
    }
  }

  private void validateParentMessage(Long conversationId, Long parentMessageId) {
    if (parentMessageId == null) {
      return;
    }
    ConversationMessage parent =
        conversationMessageRepository
            .findByIdAndConversationSessionId(parentMessageId, conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND));
    if (!parent.isAnswerMessage()) {
      throw new BusinessException(ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND);
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
