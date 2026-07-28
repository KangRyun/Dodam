package com.ssafy.b209.drawing.htp.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;

import com.ssafy.b209.auth.authorization.GuardianResourceAccessValidator;
import com.ssafy.b209.auth.service.CurrentAuthenticatedUserResolver;
import com.ssafy.b209.child.domain.Child;
import com.ssafy.b209.child.domain.ChildFixture;
import com.ssafy.b209.child.domain.ChildProfileStatus;
import com.ssafy.b209.child.domain.ChildTutorialStatus;
import com.ssafy.b209.child.repository.ChildRepository;
import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.conversation.domain.ConversationSession;
import com.ssafy.b209.conversation.repository.ConversationSessionRepository;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSession;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.domain.DrawingType;
import com.ssafy.b209.drawing.domain.DrawingTypeFixture;
import com.ssafy.b209.drawing.domain.DrawingTypeSelectableBy;
import com.ssafy.b209.drawing.htp.domain.HtpAssessment;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;
import com.ssafy.b209.drawing.htp.dto.HtpAssessmentResponse;
import com.ssafy.b209.drawing.htp.dto.StartHtpAssessmentRequest;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.global.exception.BusinessException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

@ExtendWith(MockitoExtension.class)
class HtpAssessmentServiceTest {

  private static final Long GUARDIAN_ID = 41L;
  private static final Instant NOW = Instant.parse("2026-07-28T01:00:00Z");
  private static final LocalDateTime SERVER_TIME = LocalDateTime.ofInstant(NOW, ZoneOffset.UTC);

  @Mock private ChildRepository childRepository;
  @Mock private DrawingTypeRepository drawingTypeRepository;
  @Mock private DrawingSessionRepository drawingSessionRepository;
  @Mock private HtpAssessmentRepository htpAssessmentRepository;
  @Mock private ConversationSessionRepository conversationSessionRepository;
  @Mock private CurrentAuthenticatedUserResolver currentUserResolver;
  @Mock private GuardianResourceAccessValidator accessValidator;

  private HtpAssessmentService service;
  private Child child;
  private DrawingType htpType;

  @BeforeEach
  void setUp() {
    service =
        new HtpAssessmentService(
            childRepository,
            drawingTypeRepository,
            drawingSessionRepository,
            htpAssessmentRepository,
            conversationSessionRepository,
            currentUserResolver,
            accessValidator,
            Clock.fixed(NOW, ZoneOffset.UTC));
    child =
        ChildFixture.create(
            1L,
            LocalDate.of(2018, 7, 28),
            ChildTutorialStatus.COMPLETED,
            ChildProfileStatus.ACTIVE,
            null);
    htpType =
        DrawingTypeFixture.create(
            10L, "HTP", "집·나무·사람 그림", DrawingTypeSelectableBy.GUARDIAN, 4, 12, true);
  }

  @Test
  void startsHtpWithServerSelectedHouseSubjectAndTwentyFourHourExpiry() {
    stubGuardianAndStartReferences();
    given(drawingSessionRepository.save(any(DrawingSession.class)))
        .willAnswer(
            invocation -> {
              DrawingSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", 100L);
              return session;
            });
    given(htpAssessmentRepository.saveAndFlush(any(HtpAssessment.class)))
        .willAnswer(
            invocation -> {
              HtpAssessment assessment = invocation.getArgument(0);
              ReflectionTestUtils.setField(assessment, "id", 200L);
              return assessment;
            });

    HtpAssessmentResponse response =
        service.start(
            "htp-start-key",
            new StartHtpAssessmentRequest(
                1L,
                DrawingInputMethod.CANVAS,
                OffsetDateTime.parse("2026-07-28T10:00:00+09:00"),
                null));

    assertThat(response.htpAssessmentId()).isEqualTo(200L);
    assertThat(response.currentStep().stepOrder()).isEqualTo(1);
    assertThat(response.currentStep().drawingSubject()).isEqualTo(HtpDrawingSubject.HOUSE);
    assertThat(response.currentStep().drawingSessionId()).isEqualTo(100L);
    assertThat(response.currentStep().sessionStatus()).isEqualTo(DrawingSessionStatus.IN_PROGRESS);
    assertThat(response.currentStep().currentStage()).isEqualTo(DrawingStage.DRAWING);
    assertThat(response.expiresAt()).isEqualTo(NOW.plusSeconds(24 * 60 * 60));
  }

  @Test
  void replaysConcurrentStartAfterAcquiringTheChildLock() {
    DrawingSession houseSession = persistedSession(100L, "htp-start-key");
    HtpAssessment existing =
        HtpAssessment.start(
            child, htpType, houseSession, SERVER_TIME, SERVER_TIME.plusHours(24), "htp-start-key");
    ReflectionTestUtils.setField(existing, "id", 200L);
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findByIdempotencyKey("htp-start-key"))
        .willReturn(Optional.empty());
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(htpAssessmentRepository.findByIdempotencyKeyForUpdate("htp-start-key"))
        .willReturn(Optional.of(existing));

    HtpAssessmentResponse response =
        service.start(
            "htp-start-key",
            new StartHtpAssessmentRequest(
                1L,
                DrawingInputMethod.CANVAS,
                OffsetDateTime.parse("2026-07-28T10:00:00+09:00"),
                null));

    assertThat(response.htpAssessmentId()).isEqualTo(200L);
    assertThat(response.currentStep().drawingSessionId()).isEqualTo(100L);
  }

  @Test
  void expiresStaleHtpAndAllowsAnewAssessment() {
    DrawingSession staleSession = persistedSession(90L, "old-start-key");
    HtpAssessment staleAssessment =
        HtpAssessment.start(
            child,
            htpType,
            staleSession,
            SERVER_TIME.minusHours(25),
            SERVER_TIME.minusHours(1),
            "old-start-key");
    stubGuardianAndStartReferences();
    given(htpAssessmentRepository.findActiveByChildIdForUpdate(1L))
        .willReturn(Optional.of(staleAssessment));
    given(drawingSessionRepository.findActiveByChildId(1L)).willReturn(Optional.empty());
    given(drawingSessionRepository.save(any(DrawingSession.class)))
        .willAnswer(
            invocation -> {
              DrawingSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", 100L);
              return session;
            });
    given(htpAssessmentRepository.saveAndFlush(any(HtpAssessment.class)))
        .willAnswer(
            invocation -> {
              HtpAssessment assessment = invocation.getArgument(0);
              ReflectionTestUtils.setField(assessment, "id", 200L);
              return assessment;
            });

    HtpAssessmentResponse response =
        service.start(
            "new-start-key",
            new StartHtpAssessmentRequest(
                1L,
                DrawingInputMethod.CANVAS,
                OffsetDateTime.parse("2026-07-28T10:00:00+09:00"),
                null));

    assertThat(staleAssessment.getStatus().name()).isEqualTo("EXPIRED");
    assertThat(staleSession.getSessionStatus()).isEqualTo(DrawingSessionStatus.DELETED);
    assertThat(response.htpAssessmentId()).isEqualTo(200L);
  }

  @Test
  void advancesCompletedHouseStepToTreeWithoutStartingPerStepReporting() {
    DrawingSession houseSession = persistedSession(100L, "htp-start-key");
    houseSession.startDrawingAnalysis();
    houseSession.finishDrawingAnalysis();
    houseSession.enterReflection();
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            houseSession,
            SERVER_TIME.minusHours(1),
            SERVER_TIME.plusHours(23),
            "htp-start-key");
    ReflectionTestUtils.setField(assessment, "id", 200L);
    ConversationSession conversation =
        ConversationSession.start(100L, "ELEMENTARY", 2, SERVER_TIME.minusMinutes(20));
    conversation.complete(ConversationCompletionReason.CHILD_REQUEST, SERVER_TIME.minusMinutes(1));

    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findDetailByIdForUpdate(200L))
        .willReturn(Optional.of(assessment));
    given(conversationSessionRepository.findByDrawingSessionId(100L))
        .willReturn(Optional.of(conversation));
    AtomicLong ids = new AtomicLong(101L);
    given(drawingSessionRepository.save(any(DrawingSession.class)))
        .willAnswer(
            invocation -> {
              DrawingSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", ids.getAndIncrement());
              return session;
            });

    HtpAssessmentResponse response = service.nextStep(200L, "htp-tree-key");

    assertThat(houseSession.getSessionStatus()).isEqualTo(DrawingSessionStatus.COMPLETED);
    assertThat(response.currentStep().stepOrder()).isEqualTo(2);
    assertThat(response.currentStep().drawingSubject()).isEqualTo(HtpDrawingSubject.TREE);
    assertThat(response.currentStep().drawingSessionId()).isEqualTo(101L);
    assertThat(response.allStepsCompleted()).isFalse();
  }

  @Test
  void rejectsNextStepUntilConversationHasCompleted() {
    DrawingSession houseSession = persistedSession(100L, "htp-start-key");
    houseSession.startDrawingAnalysis();
    houseSession.finishDrawingAnalysis();
    houseSession.enterReflection();
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            houseSession,
            SERVER_TIME.minusHours(1),
            SERVER_TIME.plusHours(23),
            "htp-start-key");
    ReflectionTestUtils.setField(assessment, "id", 200L);
    ConversationSession conversation =
        ConversationSession.start(100L, "ELEMENTARY", 2, SERVER_TIME.minusMinutes(20));
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findDetailByIdForUpdate(200L))
        .willReturn(Optional.of(assessment));
    given(conversationSessionRepository.findByDrawingSessionId(100L))
        .willReturn(Optional.of(conversation));

    assertThatThrownBy(() -> service.nextStep(200L, "htp-tree-key"))
        .isInstanceOf(BusinessException.class);
  }

  @Test
  void replaysPersonCompletionWithTheSameIdempotencyKey() {
    DrawingSession houseSession = persistedSession(100L, "htp-start-key");
    completeStep(houseSession);
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            houseSession,
            SERVER_TIME.minusHours(3),
            SERVER_TIME.plusHours(21),
            "htp-start-key");
    DrawingSession treeSession = persistedSession(101L, "htp-tree-key");
    assessment.advance(treeSession, SERVER_TIME.minusHours(2));
    completeStep(treeSession);
    DrawingSession personSession = persistedSession(102L, "htp-person-key");
    assessment.advance(personSession, SERVER_TIME.minusHours(1));
    personSession.startDrawingAnalysis();
    personSession.finishDrawingAnalysis();
    personSession.enterReflection();
    ReflectionTestUtils.setField(assessment, "id", 200L);
    ConversationSession conversation =
        ConversationSession.start(102L, "ELEMENTARY", 2, SERVER_TIME.minusMinutes(20));
    conversation.complete(ConversationCompletionReason.CHILD_REQUEST, SERVER_TIME.minusMinutes(1));
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findDetailByIdForUpdate(200L))
        .willReturn(Optional.of(assessment));
    given(conversationSessionRepository.findByDrawingSessionId(102L))
        .willReturn(Optional.of(conversation));

    HtpAssessmentResponse first = service.nextStep(200L, "htp-finish-key");
    HtpAssessmentResponse replay = service.nextStep(200L, "htp-finish-key");

    assertThat(first.allStepsCompleted()).isTrue();
    assertThat(replay.allStepsCompleted()).isTrue();
    assertThat(replay.currentStep().drawingSessionId()).isEqualTo(102L);
  }

  @Test
  void abandonsAggregateAndSoftDeletesItsActiveDrawingSession() {
    DrawingSession houseSession = persistedSession(100L, "htp-start-key");
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            houseSession,
            SERVER_TIME.minusHours(1),
            SERVER_TIME.plusHours(23),
            "htp-start-key");
    ReflectionTestUtils.setField(assessment, "id", 200L);
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findDetailByIdForUpdate(200L))
        .willReturn(Optional.of(assessment));

    HtpAssessmentResponse response = service.abandon(200L, "htp-abandon-key");

    assertThat(response.status().name()).isEqualTo("ABANDONED");
    assertThat(houseSession.getSessionStatus()).isEqualTo(DrawingSessionStatus.DELETED);
  }

  private void stubGuardianAndStartReferences() {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findByCode("HTP")).willReturn(Optional.of(htpType));
    given(drawingSessionRepository.findActiveByChildId(1L)).willReturn(Optional.empty());
    given(htpAssessmentRepository.findActiveByChildIdForUpdate(1L)).willReturn(Optional.empty());
  }

  private DrawingSession persistedSession(Long id, String key) {
    DrawingSession session =
        DrawingSession.start(child, htpType, DrawingInputMethod.CANVAS, SERVER_TIME, key);
    ReflectionTestUtils.setField(session, "id", id);
    return session;
  }

  private void completeStep(DrawingSession session) {
    session.startDrawingAnalysis();
    session.finishDrawingAnalysis();
    session.enterReflection();
    session.completeHtpStep(SERVER_TIME.minusMinutes(30));
  }
}
