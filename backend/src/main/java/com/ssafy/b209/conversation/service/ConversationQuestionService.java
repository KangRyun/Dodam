package com.ssafy.b209.conversation.service;

import com.ssafy.b209.analysis.repository.AnalysisObservationResultRepository;
import com.ssafy.b209.conversation.config.ConversationQuestionLimitProperties;
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
import com.ssafy.b209.conversation.repository.ConversationMessageRepository;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.htp.domain.HtpAssessmentStep;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
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

  /** 앞 주제 노트의 주제당 아이 답변 상한 — 질문 상한(htp-per-subject=5)과 같은 수다(989). */
  private static final int MAX_UTTERANCES_PER_SUBJECT = 5;

  private static final Logger log = LoggerFactory.getLogger(ConversationQuestionService.class);
  private static final String FALLBACK_TEMPLATE_TYPE = "FALLBACK";

  /**
   * 끝난 대화를 다시 열 수 있는 유일한 활동 유형이다({@code DrawingAnalysisActivityType.ART_DIARY}).
   *
   * <p>화이트리스트로 둔 것은 의도다 — "HTP만 아니면 연다"로 적으면 나중에 활동 유형이 하나 늘 때 아무도 결정하지 않은 재개가 조용히 켜진다.
   */
  private static final String REOPENABLE_ACTIVITY_TYPE = "ART_DIARY";

  private final ConversationSessionRepository conversationSessionRepository;
  private final AiQuestionTemplateRepository questionTemplateRepository;
  private final AiQuestionTemplateOptionRepository questionTemplateOptionRepository;
  private final AiQuestionClient aiQuestionClient;
  private final QuestionPersistenceService questionPersistenceService;
  // 그림 서술(VLM) 조회용 — 질문 생성 입력을 채운다(S15P11B209-704).
  private final AnalysisObservationResultRepository observationResultRepository;
  private final HtpAssessmentRepository htpAssessmentRepository;
  private final ConversationMessageRepository conversationMessageRepository;
  // 재개 예정 세션의 AI 페이싱 문맥 계산용 — 상한 변경은 QuestionPersistenceService 소관이다.
  private final ConversationQuestionLimitProperties questionLimits;

  /**
   * AI 질문 생성·폴백·저장 흐름의 의존성을 생성한다.
   *
   * @param conversationSessionRepository 대화 상태 조회 경계
   * @param questionTemplateRepository 활성 폴백 템플릿 조회 경계
   * @param questionTemplateOptionRepository 폴백 선택지 Snapshot 조회 경계
   * @param aiQuestionClient 최신 내부 AI 계약 호출 경계
   * @param questionPersistenceService 세션 잠금 기반 원자 저장 경계
   * @param observationResultRepository 그림 서술(VLM) 조회 경계 (S15P11B209-704)
   * @param questionLimits 활동 유형별 질문 상한 설정(재개 후 상한 계산에 사용)
   */
  public ConversationQuestionService(
      ConversationSessionRepository conversationSessionRepository,
      AiQuestionTemplateRepository questionTemplateRepository,
      AiQuestionTemplateOptionRepository questionTemplateOptionRepository,
      AiQuestionClient aiQuestionClient,
      QuestionPersistenceService questionPersistenceService,
      AnalysisObservationResultRepository observationResultRepository,
      HtpAssessmentRepository htpAssessmentRepository,
      ConversationMessageRepository conversationMessageRepository,
      ConversationQuestionLimitProperties questionLimits) {
    this.conversationSessionRepository = conversationSessionRepository;
    this.questionTemplateRepository = questionTemplateRepository;
    this.questionTemplateOptionRepository = questionTemplateOptionRepository;
    this.aiQuestionClient = aiQuestionClient;
    this.questionPersistenceService = questionPersistenceService;
    this.observationResultRepository = observationResultRepository;
    this.htpAssessmentRepository = htpAssessmentRepository;
    this.conversationMessageRepository = conversationMessageRepository;
    this.questionLimits = questionLimits;
  }

  /**
   * 내부 AI 계약으로 다음 질문을 생성하고 검증된 결과 또는 폴백 질문을 저장한다.
   *
   * <p>AI 요청에는 계약에 정의된 {@code recentMessages}만 전달하며, 외부의 {@code previousAnswerMessageId}는 JSON 필드로
   * 추가하지 않고 저장 시 부모 메시지로만 전달한다. 안전 정책 차단·schema 불일치·연결·timeout 오류는 모두 활성 폴백 템플릿 질문으로 잇는다 — 어느 경우에도
   * AI가 만든 문장은 저장하지 않는다.
   *
   * @param command 대화·그림·분석·난이도 문맥, 허용 응답 방식, 최근 메시지와 부모 답변 식별자
   * @return 새로 저장된 AI 질문 및 Snapshot
   * @throws BusinessException 세션 상태·질문 상한·폴백 템플릿 계약을 위반한 경우
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
    boolean reopenAllowed = isReopenAllowed(command, session);
    if (session.isCompleted()) {
      // 상한 도달로 끝난 그림일기 대화는 캔버스가 바뀌면 다시 열 수 있다. 여기는 잠금 밖이라 통과 여부만
      //   판정하고, 실제 재개는 QuestionPersistenceService 가 잠금 안에서 한다.
      //   지금 상태가 COMPLETED 이므로 아래 isConversing·canAskQuestion 검사는 건너뛴다 —
      //   재개하면 상태는 CONVERSING 이 되고 상한도 함께 올라간다.
      if (!reopenAllowed) {
        throw new BusinessException(ConversationErrorCode.CONVERSATION_ALREADY_COMPLETED);
      }
    } else if (!session.isConversing()) {
      throw new BusinessException(ConversationStartErrorCode.INVALID_STATE_TRANSITION);
    } else if (!session.canAskQuestion()) {
      throw new BusinessException(ConversationErrorCode.QUESTION_LIMIT_REACHED);
    }

    String requestId = UUID.randomUUID().toString();
    AiQuestionRequest request = toAiRequest(command, session, reopenAllowed);
    try {
      AiQuestionResponse response = aiQuestionClient.generate(request, requestId);
      if (response == null
          || !response.isContractValidFor(Set.copyOf(command.allowedResponseModes()))) {
        log.warn("AI question response schema invalid. requestId={}", requestId);
        return saveFallback(
            command.conversationId(),
            command.allowedResponseModes(),
            command.previousAnswerMessageId(),
            reopenAllowed);
      }
      // 종료 확인 신호는 저장하지 않고 이번 응답에만 싣는다(S15P11B209-951). 질문 메시지에
      // 남길 내용이 아니라 "아이가 방금 확인했다"는 관찰 보고이며, 실제 종료는 FE가 한다.
      return questionPersistenceService
          .save(
              command.conversationId(),
              new QuestionCandidate(
                  response.questionText(),
                  response.options(),
                  response.targetObject(),
                  null,
                  response.fallbackUsed(),
                  command.previousAnswerMessageId(),
                  reopenAllowed))
          .withConfirmedStopTarget(response.confirmedStopTarget());
    } catch (AiQuestionClientException exception) {
      // 안전 차단(SAFETY_POLICY_BLOCKED)도 timeout·연결 실패와 똑같이 폴백으로 잇는다.
      //   예전에는 이것만 422로 대화를 끝냈는데, 아이가 한마디 거칠게 말하면 그 뒤 AI 응답이
      //   안전 규칙에 걸릴 확률이 올라가고, 걸리는 순간 재시도 버튼도 없이 대화가 닫혔다.
      //   ⚠️ 차단된 AI 문장 자체는 여기서 절대 쓰지 않는다 — saveFallback 이 저장하는 것은
      //      사전 검증된 FALLBACK 템플릿 질문뿐이고, 차단 사유도 아이에게 노출하지 않는다.
      log.warn("AI question call failed. requestId={}, type={}", requestId, exception.getType());
      return saveFallback(
          command.conversationId(),
          command.allowedResponseModes(),
          command.previousAnswerMessageId(),
          reopenAllowed);
    }
  }

  /**
   * 이 요청이 끝난 대화를 다시 열 수 있는지 판정한다 — 상태는 바꾸지 않는다.
   *
   * <p><b>그림일기만</b> 다시 연다. HTP는 주제(집·나무·사람)마다 대화가 따로 열리고 상한까지 다 쓰고 끝나는 것이 정상 흐름인데, 그 대화를 되살리면 모든 단계
   * 대화가 COMPLETED 여야 하는 HTP 검사 완료가 막힌다. 활동 유형을 확정하지 못한 경우({@code null})도 열지 않는다 — 재개는 이미 닫힌 것을 여는
   * 동작이라, 모르면 닫아 두는 쪽이 맞다.
   *
   * <p><b>그림 활동이 아직 감정 회고 전인 단계일 때만</b> 연다({@code drawingActivityOpen}). 회고·리포트·완료로 넘어간 활동에 대화를 다시
   * 열면 이미 만들어진 리포트에 없는 말이 완료된 활동에 붙는다. 여기서 막는 것은 AI 호출을 아끼기 위한 조기 차단이고, 실제 방어선은 세션 잠금을 쥔 {@link
   * QuestionPersistenceService}가 최신 단계를 다시 읽어 세운다 — AI 호출이 도는 몇 초 사이에 활동이 회고로 넘어갈 수 있기 때문이다.
   *
   * @param command 활동 유형·활동 단계가 확정돼 실려 온 질문 생성 명령
   * @param session 조회한 대화 세션
   * @return 활동 유형·활동 단계·세션 상태가 모두 재개를 허용하면 {@code true}
   */
  private boolean isReopenAllowed(GenerateQuestionCommand command, ConversationSession session) {
    return REOPENABLE_ACTIVITY_TYPE.equals(command.activityType())
        && command.drawingActivityOpen()
        && session.isReopenEligible(ConversationQuestionLimitProperties.ABSOLUTE_MAX);
  }

  private AiQuestionRequest toAiRequest(
      GenerateQuestionCommand command, ConversationSession session, boolean reopenAllowed) {
    return new AiQuestionRequest(
        command.conversationId(),
        command.drawingSessionId(),
        command.basisAnalysisId(),
        command.childAge(),
        session.getDifficulty(),
        List.copyOf(command.allowedResponseModes()),
        session.getQuestionCount(),
        aiFacingMaxQuestionCount(session, reopenAllowed),
        List.copyOf(command.detectedObjects()),
        drawingDescriptionOf(command.basisAnalysisId()),
        List.copyOf(command.recentMessages()),
        command.safetyRuleVersion(),
        command.activityType(),
        command.drawingSubject(),
        command.askedObjectCodes(),
        previousSubjectNotes(command));
  }

  /**
   * AI에 알릴 질문 수 상한을 고른다 — 다시 열릴 세션이면 재개 후 값을 미리 싣는다.
   *
   * <p>AI는 {@code currentQuestionCount >= maxQuestionCount - 1}을 "마지막 차례"로 읽고 맺음말 성격의 질문을 만든다(AI
   * {@code _is_last_question}). 재개 대상 세션은 아직 옛 상한(=이미 던진 질문 수)을 들고 있어서, 그대로 실으면 대화를 <b>다시 여는</b> 바로
   * 그 질문이 맺음말로 나온다.
   *
   * <p>상한을 실제로 올리는 것은 잠금을 쥔 {@link QuestionPersistenceService}이며 여기서는 같은 규칙으로 계산만 한다. 재개가 실패해도(경쟁
   * 요청이 먼저 재개해 상한이 이미 올라간 경우 등) 저장 단계가 상한을 다시 검사하므로 이 값이 앞서 나가도 저장이 느슨해지지 않는다.
   *
   * @param session 조회한 대화 세션
   * @param reopenAllowed 이 요청이 대화를 다시 열 수 있는지 여부
   * @return 재개 대상이면 재개 후 상한, 아니면 현재 상한
   */
  private int aiFacingMaxQuestionCount(ConversationSession session, boolean reopenAllowed) {
    if (!reopenAllowed) {
      return session.getMaxQuestionCount();
    }
    return session.reopenedMaxQuestionCount(
        questionLimits.artDiary(), ConversationQuestionLimitProperties.ABSOLUTE_MAX);
  }

  /**
   * 같은 HTP 활동에서 앞 주제 대화의 아이 답변을 모은다 (S15P11B209-989).
   *
   * <p>주제마다 대화 세션이 새로 열려 조회 범위가 세션 안으로 닫혀 있다 — 창 크기를 늘려도 앞 주제는 한 글자도 넘어오지 않는다. 여기서 {@code
   * htp_assessment_steps}로 역추적해 앞 단계 대화의 <b>아이 답만</b> 압축해 싣는다(질문까지 실으면 프롬프트가 커진다).
   *
   * <p>첫 주제·그림일기·역추적 실패는 전부 빈 목록이다 — 이 재료는 보조라, 조회가 실패해도 질문 생성 자체는 지금과 똑같이 동작해야 한다. 발화 원문은 로그에 남기지
   * 않는다(9절).
   *
   * @param command 질문 생성 명령
   * @return 앞 주제 노트 목록(단계 순서), 없으면 빈 목록
   */
  private List<AiQuestionRequest.PreviousSubjectNote> previousSubjectNotes(
      GenerateQuestionCommand command) {
    if (!"HTP".equals(command.activityType())) {
      return List.of();
    }
    try {
      return htpAssessmentRepository
          .findStepWithAssessmentByDrawingSessionId(command.drawingSessionId())
          .map(
              step ->
                  htpAssessmentRepository
                      .findPriorStepsWithDrawingSession(
                          step.getAssessment().getId(), step.getStepOrder())
                      .stream()
                      .map(this::subjectNoteOf)
                      .filter(note -> !note.childUtterances().isEmpty())
                      .toList())
          .orElseGet(List::of);
    } catch (RuntimeException exception) {
      // 보조 재료라 실패해도 질문 생성을 막지 않는다. 발화가 섞일 수 있어 예외 유형만 남긴다(9절).
      log.warn(
          "[989] 앞 주제 대화 조회 실패 — 노트 없이 진행: conversationId={}, exceptionType={}",
          command.conversationId(),
          exception.getClass().getSimpleName());
      return List.of();
    }
  }

  /**
   * 앞 단계 하나를 노트로 만든다 — 그 단계 대화 세션의 아이 답을 순서대로 담는다.
   *
   * @param priorStep 앞 단계(그림 세션 로딩됨)
   * @return 노트이며 대화가 없으면 발화 목록이 비어 있다
   */
  private AiQuestionRequest.PreviousSubjectNote subjectNoteOf(HtpAssessmentStep priorStep) {
    List<String> utterances =
        conversationSessionRepository
            .findByDrawingSessionId(priorStep.getDrawingSession().getId())
            .map(prior -> conversationMessageRepository.findChildAnswerTexts(prior.getId()))
            .orElseGet(List::of);
    // 주제당 질문 상한(5)과 같은 수로 자른다 — 정상 범위면 그대로, 비정상 데이터만 방어한다.
    List<String> capped =
        utterances.size() > MAX_UTTERANCES_PER_SUBJECT
            ? utterances.subList(0, MAX_UTTERANCES_PER_SUBJECT)
            : utterances;
    return new AiQuestionRequest.PreviousSubjectNote(
        priorStep.getDrawingSubject().name(), List.copyOf(capped));
  }

  /**
   * 근거 분석에 저장된 그림 서술(VLM)을 찾아 질문 생성 입력에 실어준다(S15P11B209-704).
   *
   * <p>객체 이름 목록만으로는 색·표정·구도를 근거로 한 질문이 나오지 않는다. 서술은 분석 시점에 이미 만들어져 저장돼 있으므로 여기서는 조회만 한다.
   *
   * <p>⚠️ 서술이 없어도 질문 생성은 계속한다. 분석 전 첫 질문, 서술 생성 실패(VLM 오류), 구버전 데이터가 모두 정상 경로다 — 이때 AI는 기존 객체 기반
   * 질문으로 동작한다. 여기서 예외를 던지면 그림 서술이라는 보조 정보 때문에 대화 자체가 끊긴다.
   *
   * @param basisAnalysisId 근거 분석 식별자. {@code null}이면 조회하지 않는다
   * @return 서술 문자열. 없으면 {@code null}
   */
  private String drawingDescriptionOf(Long basisAnalysisId) {
    if (basisAnalysisId == null) {
      return null;
    }
    return observationResultRepository
        .findLatestOverallSummary(basisAnalysisId)
        .filter(summary -> !summary.isBlank())
        .orElse(null);
  }

  private GeneratedQuestion saveFallback(
      Long conversationId,
      List<ResponseMode> allowedResponseModes,
      Long previousAnswerMessageId,
      boolean reopenAllowed) {
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
            previousAnswerMessageId,
            reopenAllowed));
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
    return new QuestionOption(option.getOptionKey(), option.getLabel(), option.getEmoji());
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
