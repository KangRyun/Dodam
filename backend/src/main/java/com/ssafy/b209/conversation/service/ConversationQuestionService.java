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
        return saveFallback(command.conversationId(), command.allowedResponseModes());
      }
      return questionPersistenceService.save(
          command.conversationId(),
          new QuestionCandidate(
              response.questionText(),
              response.options(),
              response.targetObject(),
              null,
              response.fallbackUsed()));
    } catch (AiQuestionClientException exception) {
      if (exception.getType() == AiQuestionClientException.Type.SAFETY_POLICY_BLOCKED) {
        throw new BusinessException(ConversationErrorCode.AI_SAFETY_POLICY_BLOCKED, exception);
      }
      log.warn("AI question call failed. requestId={}, type={}", requestId, exception.getType());
      return saveFallback(command.conversationId(), command.allowedResponseModes());
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
      Long conversationId, List<ResponseMode> allowedResponseModes) {
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
            true));
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
