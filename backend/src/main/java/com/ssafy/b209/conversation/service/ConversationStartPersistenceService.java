package com.ssafy.b209.conversation.service;

import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.analysis.service.DrawingAnalysisActivityContextResolver;
import com.ssafy.b209.conversation.config.ConversationQuestionLimitProperties;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartChildProfile;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.dto.StartConversationResponse;
import com.ssafy.b209.conversation.exception.ActiveConversationExistsException;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationStartChildProfileRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 대화 시작의 권한·상태 검증과 세션 생성·단계 전이를 하나의 트랜잭션으로 처리한다. */
@Service
public class ConversationStartPersistenceService {
  private static final Logger log =
      LoggerFactory.getLogger(ConversationStartPersistenceService.class);
  private final DrawingAnalysisRepository analysisRepository;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final ConversationStartChildProfileRepository childProfileRepository;
  private final ConversationStartAuthorizationRepository authorizationRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final DrawingSessionRepository drawingSessionDetailRepository;
  private final DrawingAnalysisActivityContextResolver activityContextResolver;
  private final ConversationQuestionLimitProperties questionLimits;
  private final Clock clock;

  /**
   * 대화 시작 영속성 의존성을 생성한다.
   *
   * @param analysisRepository 그림 작성 중 대화 시작 근거 분석 조회 경계
   * @param drawingSessionRepository 그림 활동 세션 잠금 조회 경계
   * @param childProfileRepository 아동 난이도 Snapshot 조회 경계
   * @param authorizationRepository 관계·동의 검증 경계
   * @param conversationSessionRepository 대화 세션 저장 경계
   * @param drawingSessionDetailRepository 활동 유형 확정을 위한 그림 세션 상세 조회 경계
   * @param activityContextResolver 저장된 세션에서 활동 유형을 확정하는 경계
   * @param questionLimits 활동 유형별 질문 수 상한 설정
   * @param clock 서버 시각 경계
   */
  public ConversationStartPersistenceService(
      DrawingAnalysisRepository analysisRepository,
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      ConversationStartChildProfileRepository childProfileRepository,
      ConversationStartAuthorizationRepository authorizationRepository,
      ConversationSessionRepository conversationSessionRepository,
      DrawingSessionRepository drawingSessionDetailRepository,
      DrawingAnalysisActivityContextResolver activityContextResolver,
      ConversationQuestionLimitProperties questionLimits,
      Clock clock) {
    this.analysisRepository = analysisRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.childProfileRepository = childProfileRepository;
    this.authorizationRepository = authorizationRepository;
    this.conversationSessionRepository = conversationSessionRepository;
    this.drawingSessionDetailRepository = drawingSessionDetailRepository;
    this.activityContextResolver = activityContextResolver;
    this.questionLimits = questionLimits;
    this.clock = clock;
  }

  /**
   * 보호자가 소유한 그림 활동에 진행 중 대화 세션을 생성한다.
   *
   * @param guardianUserId 임시 인증 계층이 제공한 보호자 식별자
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param request 최종 API 명세의 시작 요청
   * @return 생성된 대화 세션 공개 응답
   * @throws ActiveConversationExistsException 진행 중인 기존 대화가 있어 그 식별자를 반환해야 하는 경우
   * @throws BusinessException 권한·동의·상태 규칙을 위반한 경우
   */
  @Transactional
  public StartConversationResponse create(
      Long guardianUserId, Long drawingSessionId, StartConversationRequest request) {
    ConversationStartDrawingSession drawingSession =
        drawingSessionRepository
            .findActiveByIdForUpdate(drawingSessionId)
            .orElseThrow(
                () -> new BusinessException(ConversationStartErrorCode.RESOURCE_NOT_FOUND));
    if (!authorizationRepository.hasGuardianChildRelation(
        guardianUserId, drawingSession.getChildId())) {
      throw new BusinessException(ConversationStartErrorCode.RESOURCE_OWNERSHIP_DENIED);
    }
    if (!authorizationRepository.hasRequiredConsents(drawingSession.getChildId())) {
      throw new BusinessException(ConversationStartErrorCode.REQUIRED_CONSENT_MISSING);
    }
    boolean hasUsableIntermediateAnalysis =
        request != null
            && request.analysisId() != null
            && analysisRepository.isUsableIntermediateConversationBasis(
                drawingSessionId, request.analysisId());
    if (!drawingSession.canStartConversation(hasUsableIntermediateAnalysis)) {
      throw new BusinessException(ConversationStartErrorCode.INVALID_STATE_TRANSITION);
    }
    conversationSessionRepository
        .findByDrawingSessionId(drawingSessionId)
        .ifPresent(
            existing -> {
              throw new ActiveConversationExistsException(existing.getId());
            });
    ConversationStartChildProfile child =
        childProfileRepository
            .findById(drawingSession.getChildId())
            .orElseThrow(
                () -> new BusinessException(ConversationStartErrorCode.RESOURCE_NOT_FOUND));
    int maxQuestionCount = resolveMaxQuestionCount(drawingSessionId, request);
    Instant now = clock.instant();
    try {
      ConversationSession created =
          conversationSessionRepository.saveAndFlush(
              ConversationSession.start(
                  drawingSessionId,
                  child.getQuestionDifficulty().name(),
                  maxQuestionCount,
                  LocalDateTime.ofInstant(now, ZoneOffset.UTC)));
      drawingSession.moveToConversing();
      return new StartConversationResponse(
          created.getId(),
          drawingSessionId,
          created.getConversationStatus(),
          created.getDifficultySnapshot(),
          created.getMaxQuestionCount(),
          created.getQuestionCount(),
          "REQUEST_NEXT_QUESTION",
          now);
    } catch (DataIntegrityViolationException exception) {
      throw new BusinessException(
          ConversationStartErrorCode.CONVERSATION_START_CONFLICT, exception);
    }
  }

  /**
   * 이 대화가 던질 수 있는 질문 수를 서버 정책으로 확정한다 (S15P11B209-976).
   *
   * <p>상한을 정하는 주체가 클라이언트에서 서버로 넘어온 지점이다. 이전에는 앱이 보낸 값을 그대로 쓰고 요청이 비었을 때만 상수 10을 썼는데, 앱이 항상 10을 보내고
   * 있어 서버 기본값은 한 번도 쓰인 적이 없었다 — 사실상 앱이 정책 소유자였다.
   *
   * <p>요청이 값을 보내면 <b>정책보다 낮출 때만</b> 받아들인다. 이유는 둘이다. 첫째, 아직 배포되지 않은 구 버전 앱이 계속 10을 보내는데 그 값을 그대로 쓰면
   * 정책이 앱 교체 전까지 아무 효과가 없다. 둘째, "더 짧게 하고 싶다"는 요구는 정책이 지키려는 것(너무 길어지지 않게)과 충돌하지 않으므로 굳이 막을 이유가 없다.
   * 요청 DTO의 {@code @Max} 는 남겨 둔 안전 상한이고, 실제 구속력은 여기에 있다.
   *
   * @param drawingSessionId 대화가 붙는 그림 활동 세션 식별자
   * @param request 공개 시작 요청, 없을 수 있다
   * @return 세션에 박아 둘 질문 수 상한
   */
  private int resolveMaxQuestionCount(Long drawingSessionId, StartConversationRequest request) {
    int policy = questionLimits.limitFor(resolveActivityType(drawingSessionId));
    Integer requested = request == null ? null : request.maxQuestionCount();
    return requested == null ? policy : Math.min(requested, policy);
  }

  /**
   * 활동 유형을 클라이언트 입력이 아니라 저장된 세션 관계에서 확정한다.
   *
   * <p>판별 근거는 그림 유형과 {@code htp_assessment_steps} 연결이다({@link
   * DrawingAnalysisActivityContextResolver} — 분석·질문 경로가 이미 쓰는 것과 같은 경계). 요청 Body에는 활동 유형이 없고, 있더라도
   * 상한을 정하는 값을 클라이언트 주장으로 고를 수는 없다.
   *
   * <p>확정에 실패하면 대화를 끊지 않고 그림일기 상한으로 진행한다. 여기서 예외를 던지면 아이 화면에서 대화가 아예 열리지 않는데, 잃는 것에 비해 얻는 것이 없다 —
   * 질문 몇 개 차이다. 같은 판단을 {@code ConversationNextQuestionService.resolveActivityContext} 가 이미 하고 있다.
   *
   * @param drawingSessionId 그림 활동 세션 식별자
   * @return 확정된 활동 유형, 확정하지 못하면 {@link DrawingAnalysisActivityType#ART_DIARY}
   */
  private DrawingAnalysisActivityType resolveActivityType(Long drawingSessionId) {
    try {
      return drawingSessionDetailRepository
          .findDetailById(drawingSessionId)
          .map(activityContextResolver::resolve)
          .map(context -> context.activityType())
          .orElseThrow(() -> new BusinessException(ConversationStartErrorCode.RESOURCE_NOT_FOUND));
    } catch (BusinessException exception) {
      // 세션 식별자만 남긴다 — 아동·보호자 식별 정보는 로그에 넣지 않는다(CLAUDE.md 9절).
      log.warn(
          "Failed to resolve activity type for question limit. drawingSessionId={}",
          drawingSessionId);
      return DrawingAnalysisActivityType.ART_DIARY;
    }
  }
}
