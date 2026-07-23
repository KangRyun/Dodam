package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.AiQuestionTemplate;
import com.ssafy.b209.conversation.domain.AiQuestionTemplateOption;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ResponseMode;
import com.ssafy.b209.conversation.dto.AiQuestionRequest;
import com.ssafy.b209.conversation.dto.AiQuestionResponse;
import com.ssafy.b209.conversation.dto.GenerateQuestionCommand;
import com.ssafy.b209.conversation.dto.GeneratedQuestion;
import com.ssafy.b209.conversation.dto.QuestionOption;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.AiQuestionTemplateOptionRepository;
import com.ssafy.b209.conversation.repository.AiQuestionTemplateRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.infrastructure.ai.AiQuestionClient;
import com.ssafy.b209.infrastructure.ai.AiQuestionClientException;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/** 목표 AI 계약 호출, 응답 검증, 템플릿 폴백 및 저장 흐름을 조정한다. */
@Service
public class ConversationQuestionService {

  private static final Logger log = LoggerFactory.getLogger(ConversationQuestionService.class);
  private static final String FALLBACK_TEMPLATE_TYPE = "FALLBACK";

  private final ConversationSessionRepository conversationSessionRepository;
  private final AiQuestionTemplateRepository questionTemplateRepository;
  private final AiQuestionTemplateOptionRepository questionTemplateOptionRepository;
  private final AiQuestionClient aiQuestionClient;
  private final QuestionPersistenceService questionPersistenceService;

  /**
   * AI 질문 생성·폴백·저장 흐름의 의존성을 생성한다.
   *
   * @param conversationSessionRepository 대화 상태 조회 경계
   * @param questionTemplateRepository 활성 폴백 템플릿 조회 경계
   * @param questionTemplateOptionRepository 폴백 선택지 Snapshot 조회 경계
   * @param aiQuestionClient 최신 내부 AI 계약 호출 경계
   * @param questionPersistenceService 세션 잠금 기반 원자 저장 경계
   */
  public ConversationQuestionService(
      ConversationSessionRepository conversationSessionRepository,
      AiQuestionTemplateRepository questionTemplateRepository,
      AiQuestionTemplateOptionRepository questionTemplateOptionRepository,
      AiQuestionClient aiQuestionClient,
      QuestionPersistenceService questionPersistenceService) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.questionTemplateRepository = questionTemplateRepository;
    this.questionTemplateOptionRepository = questionTemplateOptionRepository;
    this.aiQuestionClient = aiQuestionClient;
    this.questionPersistenceService = questionPersistenceService;
  }

  /**
   * 내부 AI 계약으로 다음 질문을 생성하고 검증된 결과 또는 폴백 질문을 저장한다.
   *
   * <p>AI 요청에는 계약에 정의된 {@code recentMessages}만 전달하며, 외부의 {@code previousAnswerMessageId}는 JSON 필드로
   * 추가하지 않고 저장 시 부모 메시지로만 전달한다. 안전 정책 차단은 저장하지 않고 422로 종료하며, schema·연결·timeout 오류는 활성 폴백 템플릿을 저장한다.
   *
   * @param command 대화·그림·분석·난이도 문맥, 허용 응답 방식, 최근 메시지와 부모 답변 식별자
   * @return 새로 저장된 AI 질문 및 Snapshot
   * @throws BusinessException 세션 상태·질문 상한·안전 정책·폴백 템플릿 계약을 위반한 경우
   */
  public GeneratedQuestion generateQuestion(GenerateQuestionCommand command) {
    validateCommand(command);
    ConversationSession session =
        conversationSessionRepository
            .findById(command.conversationId())
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    if (!session.getDrawingSessionId().equals(command.drawingSessionId())) {
      throw new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND);
    }
    if (session.isCompleted()) {
      throw new BusinessException(ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);
    }
    if (!session.isConversing()) {
      throw new BusinessException(ConversationStartErrorCode.INVALID_STATE_TRANSITION);
    }
    if (!session.canAskQuestion()) {
      throw new BusinessException(ConversationErrorCode.QUESTION_LIMIT_REACHED);
    }

    String requestId = UUID.randomUUID().toString();
    AiQuestionRequest request = toAiRequest(command, session);
    try {
      AiQuestionResponse response = aiQuestionClient.generate(request, requestId);
      if (response == null
          || !response.isContractValidFor(Set.copyOf(command.allowedResponseModes()))) {
        log.warn("AI question response schema invalid. requestId={}", requestId);
        return saveFallback(
            command.conversationId(),
            command.allowedResponseModes(),
            command.previousAnswerMessageId());
      }
      return questionPersistenceService.save(
          command.conversationId(),
          new QuestionCandidate(
              response.questionText(),
              response.options(),
              response.targetObject(),
              null,
              response.fallbackUsed(),
              command.previousAnswerMessageId()));
    } catch (AiQuestionClientException exception) {
      if (exception.getType() == AiQuestionClientException.Type.SAFETY_POLICY_BLOCKED) {
        throw new BusinessException(ConversationErrorCode.AI_SAFETY_POLICY_BLOCKED, exception);
      }
      log.warn("AI question call failed. requestId={}, type={}", requestId, exception.getType());
      return saveFallback(
          command.conversationId(),
          command.allowedResponseModes(),
          command.previousAnswerMessageId());
    }
  }

  private AiQuestionRequest toAiRequest(
      GenerateQuestionCommand command, ConversationSession session) {
    return new AiQuestionRequest(
        command.conversationId(),
        command.drawingSessionId(),
        command.basisAnalysisId(),
        command.childAge(),
        session.getDifficulty(),
        List.copyOf(command.allowedResponseModes()),
        session.getQuestionCount(),
        session.getMaxQuestionCount(),
        List.copyOf(command.detectedObjects()),
        List.copyOf(command.recentMessages()),
        command.safetyRuleVersion());
  }

  private GeneratedQuestion saveFallback(
      Long conversationId, List<ResponseMode> allowedResponseModes, Long previousAnswerMessageId) {
    AiQuestionTemplate template =
        questionTemplateRepository
            .findFirstByTemplateTypeAndActiveTrueOrderByIdAsc(FALLBACK_TEMPLATE_TYPE)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.FALLBACK_QUESTION_NOT_FOUND));
    return questionPersistenceService.save(
        conversationId,
        new QuestionCandidate(
            template.getQuestionText(),
            allowedResponseModes.contains(ResponseMode.OPTION)
                ? parseTemplateOptions(template.getId())
                : null,
            null,
            template.getId(),
            true,
            previousAnswerMessageId));
  }

  private List<QuestionOption> parseTemplateOptions(Long templateId) {
    List<QuestionOption> options =
        questionTemplateOptionRepository
            .findByQuestionTemplateIdOrderByDisplayOrderAsc(templateId)
            .stream()
            .map(this::toQuestionOption)
            .toList();
    if (!areValidOptions(options)) {
      throw new BusinessException(ConversationErrorCode.FALLBACK_QUESTION_NOT_FOUND);
    }
    return options;
  }

  private QuestionOption toQuestionOption(AiQuestionTemplateOption option) {
    if (option == null) {
      return null;
    }
    return new QuestionOption(option.getOptionKey(), option.getLabel());
  }

  private boolean areValidOptions(List<QuestionOption> options) {
    if (options == null || options.isEmpty()) {
      return false;
    }
    Set<String> codes = new java.util.HashSet<>();
    for (QuestionOption option : options) {
      if (option == null
          || option.code() == null
          || option.code().isBlank()
          || option.label() == null
          || option.label().isBlank()
          || !codes.add(option.code())) {
        return false;
      }
    }
    return true;
  }

  private void validateCommand(GenerateQuestionCommand command) {
    if (command == null
        || command.conversationId() == null
        || command.conversationId() <= 0
        || command.drawingSessionId() == null
        || command.drawingSessionId() <= 0
        || command.childAge() <= 0
        || command.allowedResponseModes() == null
        || command.allowedResponseModes().isEmpty()
        || command.allowedResponseModes().size()
            != Set.copyOf(command.allowedResponseModes()).size()
        || command.detectedObjects() == null
        || command.recentMessages() == null
        || command.safetyRuleVersion() == null
        || command.safetyRuleVersion().isBlank()) {
      throw new IllegalArgumentException("Invalid AI question generation command");
    }
    for (var detectedObject : command.detectedObjects()) {
      if (detectedObject == null
          || detectedObject.objectCode() == null
          || detectedObject.objectCode().isBlank()
          || detectedObject.confidence() < 0
          || detectedObject.confidence() > 1
          || detectedObject.boundingBox() == null
          || !detectedObject.boundingBox().isNormalized()) {
        throw new IllegalArgumentException("Invalid detected object");
      }
    }
  }
}
