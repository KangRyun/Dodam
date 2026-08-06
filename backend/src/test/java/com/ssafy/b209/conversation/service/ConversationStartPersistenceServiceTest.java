package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.analysis.service.DrawingAnalysisActivityContext;
import com.ssafy.b209.analysis.service.DrawingAnalysisActivityContextResolver;
import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.conversation.config.ConversationQuestionLimitProperties;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.domain.ConversationStartChildProfile;
import com.ssafy.b209.conversation.domain.ConversationStartDrawingSession;
import com.ssafy.b209.conversation.dto.StartConversationRequest;
import com.ssafy.b209.conversation.exception.ActiveConversationExistsException;
import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.conversation.repository.ConversationStartAuthorizationRepository;
import com.ssafy.b209.conversation.repository.ConversationStartChildProfileRepository;
import com.ssafy.b209.conversation.repository.ConversationStartDrawingSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.lang.reflect.Constructor;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class ConversationStartPersistenceServiceTest {
  /** 실제 설정값(application.yml)과 같은 정책. 3·5 라는 숫자가 어디서 오는지 여기서 한 번만 정한다. */
  private static final ConversationQuestionLimitProperties QUESTION_LIMITS =
      new ConversationQuestionLimitProperties(3, 5);

  @Mock private DrawingAnalysisRepository analysisRepository;
  @Mock private ConversationStartDrawingSessionRepository drawingSessionRepository;
  @Mock private ConversationStartChildProfileRepository childProfileRepository;
  @Mock private ConversationStartAuthorizationRepository authorizationRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private DrawingSessionRepository drawingSessionDetailRepository;
  @Mock private DrawingAnalysisActivityContextResolver activityContextResolver;

  private ConversationStartPersistenceService service;

  @BeforeEach
  void setUp() {
    service =
        new ConversationStartPersistenceService(
            analysisRepository,
            drawingSessionRepository,
            childProfileRepository,
            authorizationRepository,
            conversationSessionRepository,
            drawingSessionDetailRepository,
            activityContextResolver,
            QUESTION_LIMITS,
            Clock.fixed(Instant.parse("2026-07-21T02:30:00Z"), ZoneOffset.UTC));
  }

  @Test
  void createsConversationAndMovesDrawingStage() throws Exception {
    ConversationStartDrawingSession drawingSession = drawingSession();
    ConversationStartChildProfile child = child("LOWER_ELEMENTARY");
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(1L)).willReturn(true);
    given(conversationSessionRepository.findByDrawingSessionId(100L)).willReturn(Optional.empty());
    given(childProfileRepository.findById(1L)).willReturn(Optional.of(child));
    givenActivityType(DrawingAnalysisActivityType.ART_DIARY);
    given(conversationSessionRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", 800L);
              return session;
            });

    var response = service.create(9L, 100L, new StartConversationRequest(700L, 5));

    assertThat(response.conversationId()).isEqualTo(800L);
    assertThat(response.difficulty()).isEqualTo("LOWER_ELEMENTARY");
    assertThat(response.questionCount()).isZero();
    assertThat(response.nextAction()).isEqualTo("REQUEST_NEXT_QUESTION");
    assertThat(ReflectionTestUtils.getField(drawingSession, "currentStage"))
        .isEqualTo(DrawingStage.CONVERSING);
    verify(conversationSessionRepository).saveAndFlush(any(ConversationSession.class));
  }

  @Test
  void createsConversationFromIntermediateAnalysisWithoutLeavingDrawingStage() throws Exception {
    ConversationStartDrawingSession drawingSession = drawingSession(DrawingStage.DRAWING);
    ConversationStartChildProfile child = child("LOWER_ELEMENTARY");
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(1L)).willReturn(true);
    given(analysisRepository.isUsableIntermediateConversationBasis(100L, 700L)).willReturn(true);
    given(conversationSessionRepository.findByDrawingSessionId(100L)).willReturn(Optional.empty());
    given(childProfileRepository.findById(1L)).willReturn(Optional.of(child));
    givenActivityType(DrawingAnalysisActivityType.ART_DIARY);
    given(conversationSessionRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", 800L);
              return session;
            });

    var response = service.create(9L, 100L, new StartConversationRequest(700L, 5));

    assertThat(response.conversationId()).isEqualTo(800L);
    assertThat(ReflectionTestUtils.getField(drawingSession, "currentStage"))
        .isEqualTo(DrawingStage.DRAWING);
  }

  @Test
  void rejectsDrawingStageConversationWithoutIntermediateAnalysis() throws Exception {
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession(DrawingStage.DRAWING)));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(1L)).willReturn(true);

    assertThatThrownBy(() -> service.create(9L, 100L, null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.INVALID_STATE_TRANSITION));
  }

  @Test
  void rejectsGuardianWithoutChildRelation() throws Exception {
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession()));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(false);

    assertThatThrownBy(() -> service.create(9L, 100L, null))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.RESOURCE_OWNERSHIP_DENIED));
  }

  @Test
  void returnsExistingConversationIdWhenConversationAlreadyExists() throws Exception {
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession()));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(1L)).willReturn(true);
    given(conversationSessionRepository.findByDrawingSessionId(100L))
        .willReturn(Optional.of(existingConversation(800L)));

    assertThatThrownBy(() -> service.create(9L, 100L, null))
        .isInstanceOfSatisfying(
            ActiveConversationExistsException.class,
            exception -> {
              assertThat(exception.getErrorCode())
                  .isEqualTo(ConversationStartErrorCode.ACTIVE_CONVERSATION_EXISTS);
              assertThat(exception.getConversationId()).isEqualTo(800L);
            });
  }

  // ── 질문 수 상한은 서버 정책이 정한다 (S15P11B209-976) ─────────────────
  //   여기서 보는 것은 "정책값이 무엇인가"가 아니라 **그 값이 실제로 저장되는 세션에 실리는가**다.
  //   902에서 저장 메서드가 존재하기만 하고 아무도 부르지 않아 몇 주간 빈 화면이 나갔다 —
  //   그래서 설정 객체가 아니라 saveAndFlush 로 넘어간 인스턴스를 붙잡아 확인한다.

  @Test
  void appliesHtpPerSubjectLimitWhenSessionIsHtpStep() throws Exception {
    givenCreatableSession(DrawingAnalysisActivityType.HTP);

    var response = service.create(9L, 100L, null);

    assertThat(savedSession().getMaxQuestionCount()).isEqualTo(3);
    assertThat(response.maxQuestionCount()).isEqualTo(3);
  }

  @Test
  void appliesArtDiaryLimitWhenSessionIsArtDiary() throws Exception {
    givenCreatableSession(DrawingAnalysisActivityType.ART_DIARY);

    var response = service.create(9L, 100L, null);

    assertThat(savedSession().getMaxQuestionCount()).isEqualTo(5);
    assertThat(response.maxQuestionCount()).isEqualTo(5);
  }

  @Test
  void clampsClientRequestedLimitDownToPolicy() throws Exception {
    // 아직 교체되지 않은 구 버전 앱은 계속 10을 보낸다. 그 값을 그대로 받으면 정책이
    // 앱 배포 전까지 아무 효과가 없다.
    givenCreatableSession(DrawingAnalysisActivityType.HTP);

    var response = service.create(9L, 100L, new StartConversationRequest(null, 10));

    assertThat(savedSession().getMaxQuestionCount()).isEqualTo(3);
    assertThat(response.maxQuestionCount()).isEqualTo(3);
  }

  @Test
  void keepsClientRequestedLimitWhenLowerThanPolicy() throws Exception {
    // 더 짧게 하겠다는 요청은 정책이 지키려는 것과 충돌하지 않는다.
    givenCreatableSession(DrawingAnalysisActivityType.ART_DIARY);

    var response = service.create(9L, 100L, new StartConversationRequest(null, 2));

    assertThat(savedSession().getMaxQuestionCount()).isEqualTo(2);
    assertThat(response.maxQuestionCount()).isEqualTo(2);
  }

  @Test
  void fallsBackToArtDiaryLimitWhenActivityTypeCannotBeResolved() throws Exception {
    givenAuthorizedSession();
    DrawingSession detail = mock(DrawingSession.class);
    given(drawingSessionDetailRepository.findDetailById(100L)).willReturn(Optional.of(detail));
    // 출시 계약에 없는 그림 유형·끊어진 HTP 단계 연결에서 실제로 나오는 예외다.
    given(activityContextResolver.resolve(detail))
        .willThrow(new BusinessException(ConversationStartErrorCode.RESOURCE_NOT_FOUND));
    givenSavedSession();

    var response = service.create(9L, 100L, null);

    // 대화를 끊지 않는다 — 잃는 것이 질문 몇 개보다 크다.
    assertThat(response.conversationId()).isEqualTo(800L);
    assertThat(savedSession().getMaxQuestionCount()).isEqualTo(5);
  }

  private void givenCreatableSession(DrawingAnalysisActivityType activityType) throws Exception {
    givenAuthorizedSession();
    givenActivityType(activityType);
    givenSavedSession();
  }

  private void givenAuthorizedSession() throws Exception {
    given(drawingSessionRepository.findActiveByIdForUpdate(100L))
        .willReturn(Optional.of(drawingSession()));
    given(authorizationRepository.hasGuardianChildRelation(9L, 1L)).willReturn(true);
    given(authorizationRepository.hasRequiredConsents(1L)).willReturn(true);
    given(conversationSessionRepository.findByDrawingSessionId(100L)).willReturn(Optional.empty());
    given(childProfileRepository.findById(1L)).willReturn(Optional.of(child("LOWER_ELEMENTARY")));
  }

  /** 활동 유형은 요청 Body가 아니라 저장된 세션 관계에서 나온다 — 그 경계를 그대로 흉내 낸다. */
  private void givenActivityType(DrawingAnalysisActivityType activityType) {
    DrawingSession detail = mock(DrawingSession.class);
    given(drawingSessionDetailRepository.findDetailById(100L)).willReturn(Optional.of(detail));
    given(activityContextResolver.resolve(detail))
        .willReturn(
            new DrawingAnalysisActivityContext(
                activityType,
                activityType == DrawingAnalysisActivityType.HTP
                    ? DrawingAnalysisSubject.HOUSE
                    : null));
  }

  private void givenSavedSession() {
    given(conversationSessionRepository.saveAndFlush(any()))
        .willAnswer(
            invocation -> {
              ConversationSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", 800L);
              return session;
            });
  }

  private ConversationSession savedSession() {
    ArgumentCaptor<ConversationSession> captor = ArgumentCaptor.forClass(ConversationSession.class);
    verify(conversationSessionRepository).saveAndFlush(captor.capture());
    return captor.getValue();
  }

  private ConversationStartDrawingSession drawingSession() throws Exception {
    return drawingSession(DrawingStage.ANALYZING);
  }

  private ConversationStartDrawingSession drawingSession(DrawingStage stage) throws Exception {
    ConversationStartDrawingSession session = instantiate(ConversationStartDrawingSession.class);
    ReflectionTestUtils.setField(session, "id", 100L);
    ReflectionTestUtils.setField(session, "childId", 1L);
    ReflectionTestUtils.setField(
        session, "sessionStatus", com.ssafy.b209.drawing.domain.DrawingSessionStatus.IN_PROGRESS);
    ReflectionTestUtils.setField(session, "currentStage", stage);
    return session;
  }

  private ConversationStartChildProfile child(String difficulty) throws Exception {
    ConversationStartChildProfile child = instantiate(ConversationStartChildProfile.class);
    ReflectionTestUtils.setField(child, "id", 1L);
    ReflectionTestUtils.setField(
        child, "questionDifficulty", QuestionDifficulty.valueOf(difficulty));
    return child;
  }

  private ConversationSession existingConversation(Long id) throws Exception {
    ConversationSession session = instantiate(ConversationSession.class);
    ReflectionTestUtils.setField(session, "id", id);
    return session;
  }

  private <T> T instantiate(Class<T> type) throws Exception {
    Constructor<T> constructor = type.getDeclaredConstructor();
    constructor.setAccessible(true);
    return constructor.newInstance();
  }
}
