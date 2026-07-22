package com.ssafy.b209.conversation.service;

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
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 대화 시작의 권한·상태 검증과 세션 생성·단계 전이를 하나의 트랜잭션으로 처리한다. */
@Service
public class ConversationStartPersistenceService {
  private static final int DEFAULT_MAX_QUESTION_COUNT = 10;
  private final ConversationStartDrawingSessionRepository drawingSessionRepository;
  private final ConversationStartChildProfileRepository childProfileRepository;
  private final ConversationStartAuthorizationRepository authorizationRepository;
  private final ConversationSessionRepository conversationSessionRepository;
  private final Clock clock;

  /**
   * 대화 시작 영속성 의존성을 생성한다.
   *
   * @param drawingSessionRepository 그림 활동 세션 잠금 조회 경계
   * @param childProfileRepository 아동 난이도 Snapshot 조회 경계
   * @param authorizationRepository 관계·동의 검증 경계
   * @param conversationSessionRepository 대화 세션 저장 경계
   * @param clock 서버 시각 경계
   */
  public ConversationStartPersistenceService(
      ConversationStartDrawingSessionRepository drawingSessionRepository,
      ConversationStartChildProfileRepository childProfileRepository,
      ConversationStartAuthorizationRepository authorizationRepository,
      ConversationSessionRepository conversationSessionRepository,
      Clock clock) {
    this.drawingSessionRepository = drawingSessionRepository;
    this.childProfileRepository = childProfileRepository;
    this.authorizationRepository = authorizationRepository;
    this.conversationSessionRepository = conversationSessionRepository;
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
    if (!drawingSession.canStartConversation()) {
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
    int maxQuestionCount =
        request == null || request.maxQuestionCount() == null
            ? DEFAULT_MAX_QUESTION_COUNT
            : request.maxQuestionCount();
    Instant now = clock.instant();
    try {
      ConversationSession created =
          conversationSessionRepository.saveAndFlush(
              ConversationSession.start(
                  drawingSessionId,
                  child.getQuestionDifficulty(),
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
}
