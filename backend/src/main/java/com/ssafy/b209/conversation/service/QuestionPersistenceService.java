package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.config.ConversationQuestionLimitProperties;
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
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
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
 *
 * <p>상한 도달로 끝난 대화를 다시 여는 곳도 여기다({@link ConversationSession#reopen}). 재개는 상한을 올리는 상태 변경이라 잠금을 쥔 이
 * 트랜잭션 밖에서 하면 동시 요청이 상한을 두 번 올릴 수 있다. 재개 조건(활동 유형·세션 상태·그림 활동 단계)의 최종 판정도 여기서 한다 — 앞단 판정은 AI 호출 전의
 * 값이라 호출이 도는 사이에 낡을 수 있다.
 */
@Service
class QuestionPersistenceService {

  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationMessageRepository conversationMessageRepository;
  private final ConversationMessageOptionRepository conversationMessageOptionRepository;
  private final ConversationMessageTargetRepository conversationMessageTargetRepository;
  // 재개 직전 활동 단계를 잠금 안에서 다시 읽는 용도다 — 재개 경로에서만 조회한다.
  private final DrawingSessionRepository drawingSessionRepository;
  private final ConversationQuestionLimitProperties questionLimits;

  QuestionPersistenceService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationMessageRepository conversationMessageRepository,
      ConversationMessageOptionRepository conversationMessageOptionRepository,
      ConversationMessageTargetRepository conversationMessageTargetRepository,
      DrawingSessionRepository drawingSessionRepository,
      ConversationQuestionLimitProperties questionLimits) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.conversationMessageRepository = conversationMessageRepository;
    this.conversationMessageOptionRepository = conversationMessageOptionRepository;
    this.conversationMessageTargetRepository = conversationMessageTargetRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.questionLimits = questionLimits;
  }

  /**
   * 검증된 질문 후보를 현재 대화 세션에 원자적으로 저장한다.
   *
   * @param conversationId 잠글 대화 세션 식별자
   * @param candidate AI 또는 폴백으로 확정한 질문·선택지·대상·부모 답변 후보
   * @return 저장된 메시지 식별자, 순번, 정규화 Snapshot을 담은 결과
   * @throws BusinessException 세션 상태·상한·부모 답변이 유효하지 않거나(다시 열 수 없는 완료 대화 포함) 순번 UNIQUE 충돌이 발생한 경우
   */
  @Transactional
  public GeneratedQuestion save(Long conversationId, QuestionCandidate candidate) {
    ConversationSession session =
        conversationSessionRepository
            .findByIdForUpdate(conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    if (session.isCompleted()) {
      // 상한 도달로 끝난 그림일기 대화는 여기서 다시 연다. 재개 판정을 앞단(질문 생성·공개 흐름)에서도
      //   하지만, 상태를 실제로 바꾸는 곳은 잠금을 쥔 여기 하나뿐이다 — 두 요청이 동시에 들어와도
      //   상한이 두 번 올라가지 않는다. 재개 뒤 저장이 실패하면 트랜잭션이 상한 증가까지 되돌린다.
      //   ⚠️ 활동 유형 조건(candidate.reopenAllowed)을 상태 조건보다 먼저 본다. HTP는 주제 대화가
      //      상한으로 끝나는 것이 정상 흐름이고, 그 대화를 되살리면 HTP 검사 완료(모든 단계 대화가
      //      COMPLETED 여야 한다)가 막힌다. 앱도 HTP에서는 이 요청을 보내지 않지만, 방어선을 앱
      //      하나에 걸지 않는다.
      //   ⚠️ 활동 단계는 여기서 다시 읽는다. 앞단 판정은 AI 호출 <b>전</b>의 단계라, 호출이 도는 몇 초
      //      사이에 아이가 그림을 끝내고 감정 회고·리포트로 넘어갈 수 있다. 그 뒤 도착한 요청이 대화를
      //      되살리면 이미 만들어진 리포트에 없는 말이 완료된 활동에 붙는다.
      if (!candidate.reopenAllowed()
          || !session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX)
          || !isDrawingActivityOpen(session.getDrawingSessionId())) {
        throw new BusinessException(ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);
      }
      session.reopen(questionLimits.artDiary(), ConversationQuestionLimitProperties.ABSOLUTE_MAX);
    } else if (!session.isConversing()) {
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
   * 그림 활동이 아직 대화를 더 받을 수 있는 단계인지 최신 상태로 확인한다.
   *
   * <p>재개 경로에서만 부른다 — 위 조건이 {@code ||} 단축 평가로 걸러 주므로, 진행 중 대화의 일반 질문 저장은 이 조회를 하지 않는다. 잠금 안에서 늘어나는
   * 조회를 재개라는 드문 경로 하나로 묶기 위한 배치다.
   *
   * <p>이 Transaction은 AI 호출이 끝난 뒤 새로 열리고 저장소의 Open Session In View 도 꺼져 있어({@code
   * spring.jpa.open-in-view=false}) 여기서 읽는 단계는 요청 시작 시점이 아닌 <b>지금</b>의 값이다.
   *
   * <p>세션을 찾지 못하면(삭제 등) 열지 않는다 — 재개는 이미 닫힌 것을 여는 동작이라 모르면 닫아 두는 쪽이 맞다.
   *
   * @param drawingSessionId 대화가 속한 그림 활동 식별자
   * @return 재개를 받아도 되는 단계이면 {@code true}
   */
  private boolean isDrawingActivityOpen(Long drawingSessionId) {
    return drawingSessionRepository
        .findNotDeletedById(drawingSessionId)
        .map(DrawingSession::canReopenConversation)
        .orElse(false);
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
