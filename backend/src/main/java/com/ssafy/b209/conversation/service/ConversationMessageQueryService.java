package com.ssafy.b209.conversation.service;

import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationHistoryOption;
import com.ssafy.b209.conversation.domain.ConversationHistoryTarget;
import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.ConversationMessagePageResponse;
import com.ssafy.b209.conversation.dto.ConversationMessageResponse;
import com.ssafy.b209.conversation.dto.ConversationMessageSelectedResponse;
import com.ssafy.b209.conversation.dto.NextQuestionBoundingBoxResponse;
import com.ssafy.b209.conversation.dto.NextQuestionOptionResponse;
import com.ssafy.b209.conversation.dto.NextQuestionTargetResponse;
import com.ssafy.b209.conversation.dto.SelectedOptionCommand;
import com.ssafy.b209.conversation.exception.ConversationMessageListErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationHistoryOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationHistoryTargetRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageSelectedOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.conversation.repository.VoiceAnswerAuthorizationRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * CONV-02 대화 내역 조회의 소유권 검증과 메시지·선택지·대상 객체·선택 응답 조립을 담당하는 읽기 전용 서비스다.
 *
 * <p>연결 보호자의 아동 소유권을 확인한 뒤 순번 오름차순 페이지를 조회하고, 연관 데이터를 배치로 읽어 N+1 조회를 피한다. 공유 전문가 조회 경로는 유효한 리포트 공유
 * 권한 모델이 확정되기 전까지 이 서비스에서 허용하지 않는다.
 */
@Service
@Transactional(readOnly = true)
public class ConversationMessageQueryService {
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final VoiceAnswerAuthorizationRepository authorizationRepository;
  private final ConversationHistoryMessageRepository messageRepository;
  private final ConversationHistoryOptionRepository optionRepository;
  private final ConversationHistoryTargetRepository targetRepository;
  private final ConversationMessageSelectedOptionRepository selectedOptionRepository;

  /**
   * 대화 내역 조회 Use Case 의존성을 생성한다.
   *
   * @param conversationSessionRepository 대화 세션 조회 경계
   * @param drawingSessionRepository 대화와 아동을 연결하는 그림 세션 조회 경계
   * @param authorizationRepository 보호자-아동 소유권 조회 경계
   * @param messageRepository 대화 메시지 페이지 조회 경계
   * @param optionRepository 질문 선택지 Snapshot 배치 조회 경계
   * @param targetRepository 질문 대상 객체 Snapshot 배치 조회 경계
   * @param selectedOptionRepository 선택 응답 배치 조회 경계
   */
  public ConversationMessageQueryService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      VoiceAnswerAuthorizationRepository authorizationRepository,
      ConversationHistoryMessageRepository messageRepository,
      ConversationHistoryOptionRepository optionRepository,
      ConversationHistoryTargetRepository targetRepository,
      ConversationMessageSelectedOptionRepository selectedOptionRepository) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.authorizationRepository = authorizationRepository;
    this.messageRepository = messageRepository;
    this.optionRepository = optionRepository;
    this.targetRepository = targetRepository;
    this.selectedOptionRepository = selectedOptionRepository;
  }

  /**
   * 연결 보호자 소유권을 검증하고 대화 내역 한 페이지를 순번 오름차순으로 조립한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 ID
   * @param conversationId URL 대화 세션 ID
   * @param page 0부터 시작하는 페이지 번호
   * @param size 페이지 크기
   * @param afterSequence 커서 기준 순번 또는 처음부터 조회할 {@code null}
   * @return 메시지 목록과 페이지 메타데이터
   * @throws BusinessException 대화가 없거나 보호자에게 조회 권한이 없는 경우
   */
  public ConversationMessagePageResponse getMessages(
      Long guardianUserId, Long conversationId, int page, int size, Integer afterSequence) {
    ConversationSession session =
        conversationSessionRepository
            .findById(conversationId)
            .orElseThrow(
                () ->
                    new BusinessException(ConversationMessageListErrorCode.CONVERSATION_NOT_FOUND));
    authorizeGuardian(guardianUserId, session);

    Page<ConversationHistoryMessage> messagePage =
        messageRepository.findPage(conversationId, afterSequence, PageRequest.of(page, size));
    List<ConversationHistoryMessage> messages = messagePage.getContent();

    Map<Long, List<NextQuestionOptionResponse>> optionsByQuestion = loadOptions(messages);
    Map<Long, NextQuestionTargetResponse> targetByQuestion = loadTargets(messages);
    Map<Long, ConversationMessageSelectedResponse> selectedByAnswer =
        loadSelectedResponses(messages);

    List<ConversationMessageResponse> content = new ArrayList<>(messages.size());
    for (ConversationHistoryMessage message : messages) {
      content.add(toResponse(message, optionsByQuestion, targetByQuestion, selectedByAnswer));
    }
    return new ConversationMessagePageResponse(
        content,
        messagePage.getNumber(),
        messagePage.getSize(),
        messagePage.getTotalElements(),
        messagePage.getTotalPages(),
        messagePage.isFirst(),
        messagePage.isLast(),
        messagePage.hasNext());
  }

  private void authorizeGuardian(Long guardianUserId, ConversationSession session) {
    ConversationStartDrawingSession drawingSession =
        drawingSessionRepository
            .findById(session.getDrawingSessionId())
            .orElseThrow(
                () ->
                    new BusinessException(ConversationMessageListErrorCode.CONVERSATION_NOT_FOUND));
    if (!authorizationRepository.hasGuardianChildRelation(
        guardianUserId, drawingSession.getChildId())) {
      throw new BusinessException(ConversationMessageListErrorCode.CONVERSATION_ACCESS_DENIED);
    }
  }

  private Map<Long, List<NextQuestionOptionResponse>> loadOptions(
      List<ConversationHistoryMessage> messages) {
    List<Long> questionIds = collectIds(messages, ConversationHistoryMessage::isQuestion);
    Map<Long, List<NextQuestionOptionResponse>> byQuestion = new LinkedHashMap<>();
    if (questionIds.isEmpty()) {
      return byQuestion;
    }
    for (ConversationHistoryOption option :
        optionRepository
            .findByConversationMessageIdInOrderByConversationMessageIdAscDisplayOrderAsc(
                questionIds)) {
      byQuestion
          .computeIfAbsent(option.getConversationMessageId(), key -> new ArrayList<>())
          .add(
              new NextQuestionOptionResponse(
                  option.getOptionKey(),
                  option.getOptionType(),
                  option.getLabel(),
                  option.getOptionValue(),
                  option.getEmoji()));
    }
    return byQuestion;
  }

  private Map<Long, NextQuestionTargetResponse> loadTargets(
      List<ConversationHistoryMessage> messages) {
    List<Long> questionIds = collectIds(messages, ConversationHistoryMessage::isQuestion);
    Map<Long, NextQuestionTargetResponse> byQuestion = new LinkedHashMap<>();
    if (questionIds.isEmpty()) {
      return byQuestion;
    }
    for (ConversationHistoryTarget target :
        targetRepository.findByConversationMessageIdIn(questionIds)) {
      byQuestion.put(
          target.getConversationMessageId(),
          new NextQuestionTargetResponse(
              target.getObjectCode(),
              target.getObjectName(),
              new NextQuestionBoundingBoxResponse(
                  toDouble(target.getBboxX()),
                  toDouble(target.getBboxY()),
                  toDouble(target.getBboxWidth()),
                  toDouble(target.getBboxHeight()))));
    }
    return byQuestion;
  }

  private Map<Long, ConversationMessageSelectedResponse> loadSelectedResponses(
      List<ConversationHistoryMessage> messages) {
    List<Long> answerIds = collectIds(messages, ConversationHistoryMessage::isOptionAnswer);
    Map<Long, ConversationMessageSelectedResponse> byAnswer = new LinkedHashMap<>();
    if (answerIds.isEmpty()) {
      return byAnswer;
    }
    List<ConversationMessageSelectedOption> selections =
        selectedOptionRepository.findByAnswerMessageIdInOrderByAnswerMessageIdAscSelectionOrderAsc(
            answerIds);
    Map<Long, ConversationHistoryOption> optionById = loadReferencedOptions(selections);

    Map<Long, List<SelectedOptionCommand>> itemsByAnswer = new LinkedHashMap<>();
    for (ConversationMessageSelectedOption selection : selections) {
      ConversationHistoryOption option = optionById.get(selection.getMessageOptionId());
      if (option == null) {
        continue;
      }
      itemsByAnswer
          .computeIfAbsent(selection.getAnswerMessageId(), key -> new ArrayList<>())
          .add(
              new SelectedOptionCommand(
                  option.getOptionKey(),
                  option.getOptionType(),
                  option.getOptionValue(),
                  selection.getLabelSnapshot()));
    }
    Map<Long, String> directTextByAnswer = new LinkedHashMap<>();
    for (ConversationHistoryMessage message : messages) {
      if (message.isOptionAnswer()) {
        directTextByAnswer.put(message.getId(), message.getRawText());
      }
    }
    for (Long answerId : answerIds) {
      byAnswer.put(
          answerId,
          new ConversationMessageSelectedResponse(
              itemsByAnswer.getOrDefault(answerId, List.of()), directTextByAnswer.get(answerId)));
    }
    return byAnswer;
  }

  private Map<Long, ConversationHistoryOption> loadReferencedOptions(
      List<ConversationMessageSelectedOption> selections) {
    List<Long> optionIds = new ArrayList<>();
    for (ConversationMessageSelectedOption selection : selections) {
      optionIds.add(selection.getMessageOptionId());
    }
    Map<Long, ConversationHistoryOption> optionById = new LinkedHashMap<>();
    if (optionIds.isEmpty()) {
      return optionById;
    }
    for (ConversationHistoryOption option : optionRepository.findByIdIn(optionIds)) {
      optionById.put(option.getId(), option);
    }
    return optionById;
  }

  private ConversationMessageResponse toResponse(
      ConversationHistoryMessage message,
      Map<Long, List<NextQuestionOptionResponse>> optionsByQuestion,
      Map<Long, NextQuestionTargetResponse> targetByQuestion,
      Map<Long, ConversationMessageSelectedResponse> selectedByAnswer) {
    List<NextQuestionOptionResponse> options =
        message.isQuestion()
            ? optionsByQuestion.getOrDefault(message.getId(), List.of())
            : List.of();
    NextQuestionTargetResponse targetObject =
        message.isQuestion() ? targetByQuestion.get(message.getId()) : null;
    ConversationMessageSelectedResponse selectedResponse =
        message.isOptionAnswer() ? selectedByAnswer.get(message.getId()) : null;
    return new ConversationMessageResponse(
        message.getId(),
        message.getParentMessageId(),
        message.getMessageSequence(),
        message.getSenderType(),
        toPublicMessageType(message.getMessageType()),
        message.getRawText(),
        message.getSttText(),
        message.getSpeechStatus(),
        message.getSttConfidence(),
        message.isNeedsGuardianConfirmation(),
        message.isSkipped(),
        options,
        selectedResponse,
        targetObject,
        message.getCreatedAt());
  }

  private List<Long> collectIds(
      List<ConversationHistoryMessage> messages,
      java.util.function.Predicate<ConversationHistoryMessage> filter) {
    List<Long> ids = new ArrayList<>();
    for (ConversationHistoryMessage message : messages) {
      if (filter.test(message)) {
        ids.add(message.getId());
      }
    }
    return ids;
  }

  private double toDouble(BigDecimal value) {
    return value == null ? 0d : value.doubleValue();
  }

  /**
   * DB 저장 메시지 유형을 공개 API 값으로 변환한다.
   *
   * @param messageType DB {@code conversation_messages.message_type} 값
   * @return 공개 계약 §4에 정의된 공개 메시지 유형
   */
  private String toPublicMessageType(String messageType) {
    return switch (messageType) {
      case "VOICE_ANSWER" -> "ANSWER_VOICE";
      case "OPTION_ANSWER" -> "ANSWER_OPTION";
      case "TEXT_ANSWER" -> "ANSWER_TEXT";
      case "SYSTEM_NOTICE" -> "SYSTEM";
      default -> messageType;
    };
  }
}
