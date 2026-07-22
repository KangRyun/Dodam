package com.ssafy.b209.conversation.service;

import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ResponseMode;
import com.ssafy.b209.conversation.dto.DetectedObject;
import com.ssafy.b209.conversation.dto.GenerateQuestionCommand;
import com.ssafy.b209.conversation.dto.GeneratedQuestion;
import com.ssafy.b209.conversation.dto.NextQuestionBoundingBoxResponse;
import com.ssafy.b209.conversation.dto.NextQuestionOptionResponse;
import com.ssafy.b209.conversation.dto.NextQuestionRequest;
import com.ssafy.b209.conversation.dto.NextQuestionResponse;
import com.ssafy.b209.conversation.dto.NextQuestionTargetResponse;
import com.ssafy.b209.conversation.dto.PreferredResponseMode;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDate;
import java.util.EnumSet;
import java.util.List;
import org.springframework.stereotype.Service;

/** 공개 다음 질문 요청의 권한·DTO 변환을 내부 AI 질문 생성 흐름에 연결한다. */
@Service
public class ConversationNextQuestionService {
  private static final String SAFETY_RULE_VERSION = "safety-2026-07";
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationMessageRepository conversationMessageRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final ConversationStartAuthorizationRepository authorizationRepository;
  private final ChildRepository childRepository;
  private final ConversationQuestionService questionService;
  private final Clock clock;

  /**
   * 다음 질문 공개 흐름의 의존성을 생성한다.
   *
   * @param conversationSessionRepository 대화 세션 조회 경계
   * @param conversationMessageRepository 이전 답변 검증 경계
   * @param drawingSessionRepository 그림 활동-아동 연결 조회 경계
   * @param authorizationRepository 보호자 관계·필수 동의 검증 경계
   * @param childRepository AI 최소 아동 문맥 조회 경계
   * @param questionService AI 호출·폴백·원자 저장 서비스
   * @param clock 응답 생성 시각 경계
   */
  public ConversationNextQuestionService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationMessageRepository conversationMessageRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      ConversationStartAuthorizationRepository authorizationRepository,
      ChildRepository childRepository,
      ConversationQuestionService questionService,
      Clock clock) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.conversationMessageRepository = conversationMessageRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
    this.childRepository = childRepository;
    this.questionService = questionService;
    this.clock = clock;
  }

  /**
   * 보호자가 소유한 진행 중 대화에 다음 AI 질문을 저장하고 외부 DTO로 변환한다.
   *
   * <p>세션 잠금·순번·질문 수 증가·부모 메시지 재검증은 AI 호출 뒤 {@link QuestionPersistenceService}의 짧은 트랜잭션에서 다시 수행한다.
   *
   * @param guardianUserId 인증 계층이 제공한 보호자 식별자
   * @param conversationId 대화 세션 식별자
   * @param request 외부 다음 질문 요청
   * @return 저장된 질문의 외부 응답 DTO
   * @throws BusinessException 권한, 동의, 상태, 이전 답변 또는 AI 정책 검증 실패 시
   */
  public NextQuestionResponse generate(
      Long guardianUserId, Long conversationId, NextQuestionRequest request) {
    ConversationSession session =
        conversationSessionRepository
            .findById(conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    Long childId =
        drawingSessionRepository
            .findById(session.getDrawingSessionId())
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND))
            .getChildId();
    if (!authorizationRepository.hasGuardianChildRelation(guardianUserId, childId)
        || !authorizationRepository.hasRequiredConsents(childId)) {
      throw new BusinessException(ConversationErrorCode.CONVERSATION_ACCESS_DENIED);
    }
    validateCurrentState(session);
    validatePreviousAnswer(conversationId, request.previousAnswerMessageId());
    Child child =
        childRepository
            .findById(childId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    List<ResponseMode> modes = toInternalModes(request.preferredResponseModes());
    GeneratedQuestion generated =
        questionService.generateQuestion(
            new GenerateQuestionCommand(
                conversationId,
                session.getDrawingSessionId(),
                request.basisAnalysisId(),
                child.ageOn(LocalDate.now(clock)),
                modes,
                List.<DetectedObject>of(),
                List.of(),
                SAFETY_RULE_VERSION,
                request.previousAnswerMessageId()));
    return toResponse(conversationId, generated, modes.contains(ResponseMode.VOICE));
  }

  private void validateCurrentState(ConversationSession session) {
    if (session.isCompleted()) {
      throw new BusinessException(ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);
    }
    if (!session.isConversing()) {
      throw new BusinessException(ConversationStartErrorCode.INVALID_STATE_TRANSITION);
    }
    if (!session.canAskQuestion()) {
      throw new BusinessException(ConversationErrorCode.QUESTION_LIMIT_REACHED);
    }
  }

  private void validatePreviousAnswer(Long conversationId, Long previousAnswerMessageId) {
    if (previousAnswerMessageId == null) {
      return;
    }
    ConversationMessage message =
        conversationMessageRepository
            .findByIdAndConversationSessionId(previousAnswerMessageId, conversationId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND));
    if (!message.isAnswerMessage()) {
      throw new BusinessException(ConversationErrorCode.QUESTION_MESSAGE_NOT_FOUND);
    }
  }

  private List<ResponseMode> toInternalModes(List<PreferredResponseMode> externalModes) {
    if (externalModes == null || externalModes.isEmpty()) {
      throw new BusinessException(ConversationErrorCode.PREFERRED_RESPONSE_MODE_INVALID);
    }
    EnumSet<ResponseMode> mapped = EnumSet.noneOf(ResponseMode.class);
    EnumSet<PreferredResponseMode> seen = EnumSet.noneOf(PreferredResponseMode.class);
    for (PreferredResponseMode externalMode : externalModes) {
      if (externalMode == null) {
        throw new BusinessException(ConversationErrorCode.PREFERRED_RESPONSE_MODE_INVALID);
      }
      if (!seen.add(externalMode)) {
        throw new BusinessException(ConversationErrorCode.PREFERRED_RESPONSE_MODE_INVALID);
      }
      mapped.add(
          externalMode == PreferredResponseMode.VOICE ? ResponseMode.VOICE : ResponseMode.OPTION);
    }
    return List.copyOf(mapped);
  }

  private NextQuestionResponse toResponse(
      Long conversationId, GeneratedQuestion generated, boolean ttsAvailable) {
    List<NextQuestionOptionResponse> options =
        generated.options().stream().map(this::toOptionResponse).toList();
    return new NextQuestionResponse(
        generated.messageId(),
        conversationId,
        generated.sequence(),
        "AI",
        "QUESTION",
        generated.questionText(),
        options,
        toTargetResponse(generated.targetObject()),
        ttsAvailable,
        clock.instant());
  }

  private NextQuestionOptionResponse toOptionResponse(QuestionOption option) {
    return new NextQuestionOptionResponse(
        option.code(), "OPTION", option.label(), option.code(), null);
  }

  private NextQuestionTargetResponse toTargetResponse(DetectedObject target) {
    if (target == null) {
      return null;
    }
    return new NextQuestionTargetResponse(
        target.objectCode(),
        target.objectName(),
        new NextQuestionBoundingBoxResponse(
            target.boundingBox().x(),
            target.boundingBox().y(),
            target.boundingBox().width(),
            target.boundingBox().height()));
  }
}
