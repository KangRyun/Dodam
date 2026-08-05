package com.ssafy.b209.conversation.service;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import com.ssafy.b209.analysis.domain.DrawingCoordinateSpace;
import com.ssafy.b209.analysis.domain.DrawingDetectedObject;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.analysis.service.DrawingAnalysisActivityContext;
import com.ssafy.b209.analysis.service.DrawingAnalysisActivityContextResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.conversation.domain.ConversationHistoryMessage;
import com.ssafy.b209.conversation.domain.ConversationHistoryOption;
import com.ssafy.b209.conversation.domain.ConversationMessage;
import com.ssafy.b209.conversation.domain.ConversationMessageSelectedOption;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ResponseMode;
import com.ssafy.b209.conversation.dto.BoundingBox;
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
import com.ssafy.b209.conversation.dto.RecentMessage;
import com.ssafy.b209.conversation.exception.ConversationErrorCode;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationHistoryMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationHistoryOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageSelectedOptionRepository;
import com.ssafy.b209.conversation.repository.ConversationMessageTargetRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

/** 공개 다음 질문 요청의 권한·DTO 변환을 내부 AI 질문 생성 흐름에 연결한다. */
@Service
public class ConversationNextQuestionService {
  private static final Logger log = LoggerFactory.getLogger(ConversationNextQuestionService.class);
  private static final String SAFETY_RULE_VERSION = "safety-2026-07";
  private static final int RECENT_MESSAGE_LIMIT = 10;
  private final ConversationSessionRepository conversationSessionRepository;
  private final ConversationMessageRepository conversationMessageRepository;
  private final ConversationHistoryMessageRepository conversationHistoryMessageRepository;
  private final ConversationHistoryOptionRepository conversationHistoryOptionRepository;
  private final ConversationMessageSelectedOptionRepository selectedOptionRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final ConversationMessageTargetRepository conversationMessageTargetRepository;
  private final DrawingSessionRepository drawingSessionDetailRepository;
  private final DrawingAnalysisActivityContextResolver activityContextResolver;
  private final ConversationStartAuthorizationRepository authorizationRepository;
  private final ChildRepository childRepository;
  private final DrawingAnalysisRepository drawingAnalysisRepository;
  private final ConversationQuestionService questionService;
  private final Clock clock;

  /**
   * 다음 질문 공개 흐름의 의존성을 생성한다.
   *
   * @param conversationSessionRepository 대화 세션 조회 경계
   * @param conversationMessageRepository 이전 답변 검증 경계
   * @param conversationHistoryMessageRepository AI 문맥용 최근 대화 조회 경계
   * @param conversationHistoryOptionRepository 선택 답변의 옵션 Code 조회 경계
   * @param selectedOptionRepository 선택 답변의 Label과 선택 순서 조회 경계
   * @param drawingSessionRepository 그림 활동-아동 연결 조회 경계
   * @param conversationMessageTargetRepository 대화에서 이미 질문한 대상 객체 Code 조회 경계
   * @param drawingSessionDetailRepository 활동 유형·주제 확정을 위한 그림 세션 상세 조회 경계
   * @param activityContextResolver 저장된 세션에서 활동 유형·HTP 주제를 확정하는 경계
   * @param authorizationRepository 보호자 관계·필수 동의 검증 경계
   * @param childRepository AI 최소 아동 문맥 조회 경계
   * @param drawingAnalysisRepository 분석 근거와 정규화 객체 조회 경계
   * @param questionService AI 호출·폴백·원자 저장 서비스
   * @param clock 응답 생성 시각 경계
   */
  public ConversationNextQuestionService(
      ConversationSessionRepository conversationSessionRepository,
      ConversationMessageRepository conversationMessageRepository,
      ConversationHistoryMessageRepository conversationHistoryMessageRepository,
      ConversationHistoryOptionRepository conversationHistoryOptionRepository,
      ConversationMessageSelectedOptionRepository selectedOptionRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      ConversationMessageTargetRepository conversationMessageTargetRepository,
      DrawingSessionRepository drawingSessionDetailRepository,
      DrawingAnalysisActivityContextResolver activityContextResolver,
      ConversationStartAuthorizationRepository authorizationRepository,
      ChildRepository childRepository,
      DrawingAnalysisRepository drawingAnalysisRepository,
      ConversationQuestionService questionService,
      Clock clock) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.conversationMessageRepository = conversationMessageRepository;
    this.conversationHistoryMessageRepository = conversationHistoryMessageRepository;
    this.conversationHistoryOptionRepository = conversationHistoryOptionRepository;
    this.selectedOptionRepository = selectedOptionRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.conversationMessageTargetRepository = conversationMessageTargetRepository;
    this.drawingSessionDetailRepository = drawingSessionDetailRepository;
    this.activityContextResolver = activityContextResolver;
    this.authorizationRepository = authorizationRepository;
    this.childRepository = childRepository;
    this.drawingAnalysisRepository = drawingAnalysisRepository;
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
    ActivityContext activityContext = resolveActivityContext(session.getDrawingSessionId());
    List<String> askedObjectCodes =
        conversationMessageTargetRepository.findAskedObjectCodes(conversationId);
    GeneratedQuestion generated =
        questionService.generateQuestion(
            new GenerateQuestionCommand(
                conversationId,
                session.getDrawingSessionId(),
                request.basisAnalysisId(),
                child.ageOn(LocalDate.now(clock)),
                modes,
                assembleDetectedObjects(session.getDrawingSessionId(), request.basisAnalysisId()),
                assembleRecentMessages(conversationId),
                SAFETY_RULE_VERSION,
                request.previousAnswerMessageId(),
                activityContext.activityType(),
                activityContext.drawingSubject(),
                askedObjectCodes));
    return toResponse(conversationId, generated, modes.contains(ResponseMode.VOICE));
  }

  /**
   * 저장된 그림 세션 관계에서 AI에 전달할 활동 유형과 HTP 주제를 확정한다.
   *
   * <p>주제 확정에 실패하면({@link DrawingAnalysisActivityContextResolver}가 {@link BusinessException}을 던지면)
   * 대화를 끊지 않고 두 값을 {@code null}로 둔다. 정상 데이터에서는 발생하지 않는 경로이므로 세션 식별자만 남겨 경고한다.
   *
   * @param drawingSessionId 현재 대화가 속한 그림 활동 식별자
   * @return {@code enum.name()} 문자열로 담은 활동 유형·주제, 확정 실패 시 두 값 모두 {@code null}
   */
  private ActivityContext resolveActivityContext(Long drawingSessionId) {
    DrawingSession drawingSession =
        drawingSessionDetailRepository
            .findDetailById(drawingSessionId)
            .orElseThrow(
                () -> new BusinessException(ConversationErrorCode.CONVERSATION_SESSION_NOT_FOUND));
    try {
      DrawingAnalysisActivityContext context = activityContextResolver.resolve(drawingSession);
      return new ActivityContext(
          context.activityType().name(),
          context.drawingSubject() == null ? null : context.drawingSubject().name());
    } catch (BusinessException exception) {
      log.warn("Failed to resolve drawing subject context. drawingSessionId={}", drawingSessionId);
      return new ActivityContext(null, null);
    }
  }

  private record ActivityContext(String activityType, String drawingSubject) {}

  /**
   * 세션의 최근 질문·답변을 AI 요청용 최소 문맥으로 조립한다.
   *
   * <p>저장소는 순번 내림차순으로 반환하므로 실제 대화 흐름과 같도록 순번 오름차순으로 뒤집어 전달한다. 음성 답변은 인식 결과({@code sttText})를 우선
   * 사용하고 없으면 원문을 사용하며, 어떤 원문도 로그로 남기지 않는다.
   *
   * @param conversationId 대화 세션 식별자
   * @return 순번 오름차순의 최근 대화 문맥, 없으면 빈 목록
   */
  private List<RecentMessage> assembleRecentMessages(Long conversationId) {
    List<ConversationHistoryMessage> recent =
        conversationHistoryMessageRepository.findRecentContextMessages(
            conversationId, PageRequest.of(0, RECENT_MESSAGE_LIMIT));
    Map<Long, SelectedOptionContext> selectedOptionsByAnswer = loadSelectedOptionContexts(recent);
    List<RecentMessage> ordered = new ArrayList<>(recent.size());
    for (int index = recent.size() - 1; index >= 0; index--) {
      ConversationHistoryMessage message = recent.get(index);
      SelectedOptionContext selectedOptions = selectedOptionsByAnswer.get(message.getId());
      ordered.add(
          new RecentMessage(
              message.getId(),
              message.getSenderType(),
              message.getMessageType(),
              resolveContextText(message, selectedOptions),
              selectedOptions == null ? null : selectedOptions.codes()));
    }
    return List.copyOf(ordered);
  }

  private String resolveContextText(
      ConversationHistoryMessage message, SelectedOptionContext selectedOptions) {
    String sttText = message.getSttText();
    if (sttText != null && !sttText.isBlank()) {
      return sttText;
    }
    if (selectedOptions != null && !selectedOptions.labels().isEmpty()) {
      String selectedLabels = String.join(", ", selectedOptions.labels());
      String directText = message.getRawText();
      return directText == null || directText.isBlank()
          ? selectedLabels
          : selectedLabels + " / " + directText;
    }
    return message.getRawText();
  }

  private Map<Long, SelectedOptionContext> loadSelectedOptionContexts(
      List<ConversationHistoryMessage> messages) {
    List<Long> answerMessageIds = new ArrayList<>();
    for (ConversationHistoryMessage message : messages) {
      if (message.isOptionAnswer()) {
        answerMessageIds.add(message.getId());
      }
    }
    if (answerMessageIds.isEmpty()) {
      return Map.of();
    }

    List<ConversationMessageSelectedOption> selections =
        selectedOptionRepository.findByAnswerMessageIdInOrderByAnswerMessageIdAscSelectionOrderAsc(
            answerMessageIds);
    Map<Long, ConversationHistoryOption> optionById = loadSelectedOptionsById(selections);
    Map<Long, List<String>> codesByAnswer = new LinkedHashMap<>();
    Map<Long, List<String>> labelsByAnswer = new LinkedHashMap<>();
    for (ConversationMessageSelectedOption selection : selections) {
      ConversationHistoryOption option = optionById.get(selection.getMessageOptionId());
      if (option == null) {
        continue;
      }
      codesByAnswer
          .computeIfAbsent(selection.getAnswerMessageId(), ignored -> new ArrayList<>())
          .add(option.getOptionKey());
      labelsByAnswer
          .computeIfAbsent(selection.getAnswerMessageId(), ignored -> new ArrayList<>())
          .add(selection.getLabelSnapshot());
    }

    Map<Long, SelectedOptionContext> contexts = new LinkedHashMap<>();
    for (Long answerMessageId : answerMessageIds) {
      List<String> codes = codesByAnswer.get(answerMessageId);
      if (codes != null && !codes.isEmpty()) {
        contexts.put(
            answerMessageId,
            new SelectedOptionContext(
                List.copyOf(codes),
                List.copyOf(labelsByAnswer.getOrDefault(answerMessageId, List.of()))));
      }
    }
    return Map.copyOf(contexts);
  }

  private Map<Long, ConversationHistoryOption> loadSelectedOptionsById(
      List<ConversationMessageSelectedOption> selections) {
    List<Long> optionIds = new ArrayList<>(selections.size());
    for (ConversationMessageSelectedOption selection : selections) {
      optionIds.add(selection.getMessageOptionId());
    }
    if (optionIds.isEmpty()) {
      return Map.of();
    }
    Map<Long, ConversationHistoryOption> optionById = new LinkedHashMap<>();
    for (ConversationHistoryOption option :
        conversationHistoryOptionRepository.findByIdIn(optionIds)) {
      optionById.put(option.getId(), option);
    }
    return Map.copyOf(optionById);
  }

  private record SelectedOptionContext(List<String> codes, List<String> labels) {}

  /**
   * 그림 분석 근거가 있으면 탐지 객체를 AI 요청 문맥으로 조립한다.
   *
   * <p>같은 그림 활동에 속한 성공 또는 부분 성공 분석만 사용하며, 기존 픽셀 좌표 결과는 변환하지 않고 제외한다. 종합 AI 계약에서 {@link
   * DrawingCoordinateSpace#NORMALIZED}로 저장한 객체만 대화 질문 계약으로 전달한다.
   *
   * @param drawingSessionId 현재 대화가 속한 그림 활동 식별자
   * @param basisAnalysisId 그림 분석 근거 식별자 또는 근거가 없을 때의 {@code null}
   * @return 정규화 좌표를 가진 탐지 객체 목록, 사용할 근거가 없으면 빈 목록
   */
  private List<DetectedObject> assembleDetectedObjects(
      Long drawingSessionId, Long basisAnalysisId) {
    if (basisAnalysisId == null) {
      return List.of();
    }
    return drawingAnalysisRepository
        .findDetailBySessionIdAndAnalysisId(drawingSessionId, basisAnalysisId)
        .filter(this::isCompletedAnalysis)
        .stream()
        .flatMap(analysis -> analysis.getDetections().stream())
        .filter(detection -> detection.getCoordinateSpace() == DrawingCoordinateSpace.NORMALIZED)
        .map(this::toDetectedObject)
        .toList();
  }

  private boolean isCompletedAnalysis(DrawingAnalysis analysis) {
    return analysis.getState() == DrawingAnalysisState.SUCCESS
        || analysis.getState() == DrawingAnalysisState.PARTIAL_SUCCESS;
  }

  private DetectedObject toDetectedObject(DrawingDetectedObject detection) {
    return new DetectedObject(
        detection.getLabel(),
        detection.getObjectName(),
        detection.getConfidence().doubleValue(),
        new BoundingBox(
            detection.getX().doubleValue(),
            detection.getY().doubleValue(),
            detection.getWidth().doubleValue(),
            detection.getHeight().doubleValue()));
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
        clock.instant(),
        generated.confirmedStopTarget());
  }

  private NextQuestionOptionResponse toOptionResponse(QuestionOption option) {
    // 노출 type은 OPTION으로 고정한다. 저장 Snapshot의 option_type(STATIC)과 다른 값이며 선택 답변 요청은 저장 값을 보낸다.
    return new NextQuestionOptionResponse(
        option.code(), "OPTION", option.label(), option.code(), option.emoji());
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
