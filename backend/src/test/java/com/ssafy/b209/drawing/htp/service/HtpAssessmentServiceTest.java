package com.ssafy.b209.drawing.htp.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;

import com.ssafy.b209.analysis.domain.DrawingAnalysis;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.dto.DrawingAnalysisType;
import com.ssafy.b209.analysis.repository.AnalysisResultJdbcRepository;
import com.ssafy.b209.analysis.repository.DrawingAnalysisRepository;
import com.ssafy.b209.analysis.repository.UnusedAnalysisInput;
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
import com.ssafy.b209.drawing.domain.DrawingAsset;
import com.ssafy.b209.drawing.domain.DrawingAssetType;
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
import com.ssafy.b209.drawing.htp.dto.HtpCompletionResponse;
import com.ssafy.b209.drawing.htp.dto.StartHtpAssessmentRequest;
import com.ssafy.b209.drawing.htp.exception.HtpErrorCode;
import com.ssafy.b209.drawing.htp.repository.HtpAssessmentRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionEmotionRepository;
import com.ssafy.b209.drawing.repository.DrawingSessionRepository;
import com.ssafy.b209.drawing.repository.DrawingTypeRepository;
import com.ssafy.b209.drawing.service.DrawingReflectionService;
import com.ssafy.b209.drawing.service.StageFinalImageFinder;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.Report;
import com.ssafy.b209.report.repository.ReportRepository;
import com.ssafy.b209.report.service.ReportGenerationRequestedEvent;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;
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
  @Mock private DrawingSessionEmotionRepository drawingSessionEmotionRepository;
  @Mock private StageFinalImageFinder stageFinalImageFinder;
  @Mock private DrawingAnalysisRepository drawingAnalysisRepository;
  @Mock private AnalysisResultJdbcRepository analysisResultJdbcRepository;
  @Mock private ReportRepository reportRepository;
  @Mock private ApplicationEventPublisher eventPublisher;
  @Mock private DrawingReflectionService drawingReflectionService;
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
            drawingSessionEmotionRepository,
            stageFinalImageFinder,
            drawingAnalysisRepository,
            analysisResultJdbcRepository,
            reportRepository,
            eventPublisher,
            drawingReflectionService,
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
  void replacesAnActiveGeneralDrawingWithAHouseStep() {
    DrawingSession activeGeneral =
        DrawingSession.start(
            child,
            DrawingTypeFixture.create(
                7L, "ART_DIARY", "그림일기", DrawingTypeSelectableBy.GUARDIAN, 4, 12, true),
            DrawingInputMethod.CANVAS,
            SERVER_TIME.minusMinutes(20),
            "old-general-key");
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(childRepository.findNotDeletedByIdForUpdate(1L)).willReturn(Optional.of(child));
    given(drawingTypeRepository.findByCode("HTP")).willReturn(Optional.of(htpType));
    given(htpAssessmentRepository.findActiveByChildIdForUpdate(1L)).willReturn(Optional.empty());
    given(drawingSessionRepository.findActiveByChildId(1L)).willReturn(Optional.of(activeGeneral));
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
            "replace-start-key",
            new StartHtpAssessmentRequest(
                1L,
                DrawingInputMethod.CANVAS,
                OffsetDateTime.parse("2026-07-28T10:00:00+09:00"),
                null,
                true));

    assertThat(response.currentStep().drawingSubject()).isEqualTo(HtpDrawingSubject.HOUSE);
    assertThat(activeGeneral.getSessionStatus()).isEqualTo(DrawingSessionStatus.ABANDONED);
    assertThat(activeGeneral.getDeletedAt()).isNull();
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
    given(drawingSessionEmotionRepository.existsByDrawingSessionId(100L)).willReturn(true);
    AtomicLong ids = new AtomicLong(101L);
    given(drawingSessionRepository.save(any(DrawingSession.class)))
        .willAnswer(
            invocation -> {
              DrawingSession session = invocation.getArgument(0);
              ReflectionTestUtils.setField(session, "id", ids.getAndIncrement());
              return session;
            });

    HtpAssessmentResponse response =
        service.nextStep(200L, "htp-tree-key", DrawingInputMethod.UPLOAD);

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

    assertThatThrownBy(() -> service.nextStep(200L, "htp-tree-key", DrawingInputMethod.CANVAS))
        .isInstanceOf(BusinessException.class);
  }

  @Test
  void rejectsNextStepUntilCurrentSubjectReflectionHasBeenSaved() {
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
    given(drawingSessionEmotionRepository.existsByDrawingSessionId(100L)).willReturn(false);

    assertThatThrownBy(() -> service.nextStep(200L, "htp-tree-key", DrawingInputMethod.CANVAS))
        .isInstanceOf(BusinessException.class)
        .extracting(exception -> ((BusinessException) exception).getErrorCode())
        .isEqualTo(HtpErrorCode.HTP_REFLECTION_REQUIRED);
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
    given(drawingSessionEmotionRepository.existsByDrawingSessionId(102L)).willReturn(true);

    HtpAssessmentResponse first =
        service.nextStep(200L, "htp-finish-key", DrawingInputMethod.CANVAS);
    HtpAssessmentResponse replay =
        service.nextStep(200L, "htp-finish-key", DrawingInputMethod.CANVAS);

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

  @Test
  void createsExactlyOneAggregateReportAfterAllThreeStepsAreReady() {
    DrawingSession house = persistedSession(100L, "htp-start-key");
    completeStep(house);
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            house,
            SERVER_TIME.minusHours(3),
            SERVER_TIME.plusHours(21),
            "htp-start-key");
    DrawingSession tree = persistedSession(101L, "htp-tree-key");
    assessment.advance(tree, SERVER_TIME.minusHours(2));
    completeStep(tree);
    DrawingSession person = persistedSession(102L, "htp-person-key");
    assessment.advance(person, SERVER_TIME.minusHours(1));
    completeStep(person);
    ReflectionTestUtils.setField(assessment, "id", 200L);

    List<DrawingAsset> assets =
        List.of(finalAsset(house, 501L), finalAsset(tree, 502L), finalAsset(person, 503L));
    List<DrawingAnalysis> objectAnalyses =
        List.of(
            successfulObjectAnalysis(house, assets.get(0), "house-analysis"),
            successfulObjectAnalysis(tree, assets.get(1), "tree-analysis"),
            successfulObjectAnalysis(person, assets.get(2), "person-analysis"));
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findDetailByIdForUpdate(200L))
        .willReturn(Optional.of(assessment));
    stubStageFinalImages(assets);
    given(
            drawingAnalysisRepository
                .findByDrawingSessionIdInAndScopeOrderByDrawingSessionIdAscRequestedAtDescIdDesc(
                    List.of(100L, 101L, 102L), DrawingAnalysisScope.FINAL))
        .willReturn(objectAnalyses);
    given(conversationSessionRepository.findByDrawingSessionId(any()))
        .willAnswer(
            invocation ->
                Optional.of(completedConversation(invocation.getArgument(0, Long.class))));
    given(drawingAnalysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
        .willAnswer(
            invocation -> {
              DrawingAnalysis analysis = invocation.getArgument(0);
              ReflectionTestUtils.setField(analysis, "id", 900L);
              return analysis;
            });
    given(reportRepository.findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(102L))
        .willReturn(Optional.empty());
    given(reportRepository.saveAndFlush(any(Report.class)))
        .willAnswer(
            invocation -> {
              Report report = invocation.getArgument(0);
              ReflectionTestUtils.setField(report, "id", 901L);
              return report;
            });

    HtpCompletionResponse response = service.complete(200L, "htp-complete-key");

    assertThat(response.status().name()).isEqualTo("ANALYZING");
    assertThat(response.analysisId()).isEqualTo(900L);
    assertThat(response.reportId()).isEqualTo(901L);
    verify(eventPublisher).publishEvent(new ReportGenerationRequestedEvent(900L));
  }

  @Test
  void acceptsCompletionWhenEveryStageObjectDetectionFailed() {
    DrawingSession house = persistedSession(100L, "htp-start-key");
    DrawingSession tree = persistedSession(101L, "htp-tree-key");
    DrawingSession person = persistedSession(102L, "htp-person-key");
    HtpAssessment assessment = completedAssessment(house, tree, person);
    List<DrawingAsset> assets =
        List.of(finalAsset(house, 501L), finalAsset(tree, 502L), finalAsset(person, 503L));
    stubAuthorizedAssessment(assessment);
    stubStageFinalImages(assets);
    stubObjectAnalyses(
        List.of(
            failedObjectAnalysis(house, assets.get(0), "house-analysis"),
            failedObjectAnalysis(tree, assets.get(1), "tree-analysis"),
            failedObjectAnalysis(person, assets.get(2), "person-analysis")));
    stubCompletedConversations();
    stubReportCreation();

    HtpCompletionResponse response = service.complete(200L, "htp-complete-key");

    assertThat(response.status().name()).isEqualTo("ANALYZING");
    assertThat(response.analysisId()).isEqualTo(900L);
    assertThat(response.subjectsWithoutObjectDetection())
        .containsExactly(HtpDrawingSubject.HOUSE, HtpDrawingSubject.TREE, HtpDrawingSubject.PERSON);
    verify(eventPublisher).publishEvent(new ReportGenerationRequestedEvent(900L));
  }

  @Test
  void recordsOnlyTheStageWithoutObjectDetectionAsAnUnusedReportInput() {
    DrawingSession house = persistedSession(100L, "htp-start-key");
    DrawingSession tree = persistedSession(101L, "htp-tree-key");
    DrawingSession person = persistedSession(102L, "htp-person-key");
    HtpAssessment assessment = completedAssessment(house, tree, person);
    List<DrawingAsset> assets =
        List.of(finalAsset(house, 501L), finalAsset(tree, 502L), finalAsset(person, 503L));
    stubAuthorizedAssessment(assessment);
    stubStageFinalImages(assets);
    stubObjectAnalyses(
        List.of(
            successfulObjectAnalysis(house, assets.get(0), "house-analysis"),
            successfulObjectAnalysis(tree, assets.get(1), "tree-analysis")));
    stubCompletedConversations();
    stubReportCreation();

    HtpCompletionResponse response = service.complete(200L, "htp-complete-key");

    assertThat(response.subjectsWithoutObjectDetection()).containsExactly(HtpDrawingSubject.PERSON);
    ArgumentCaptor<List<UnusedAnalysisInput>> captor = ArgumentCaptor.captor();
    verify(analysisResultJdbcRepository)
        .appendUnusedInputs(eq(900L), captor.capture(), any(LocalDateTime.class));
    assertThat(captor.getValue())
        .singleElement()
        .satisfies(
            input -> {
              assertThat(input.inputName()).isEqualTo("PERSON");
              assertThat(input.sourceId()).isEqualTo(102L);
              assertThat(input.reasonCode()).isEqualTo("OBJECT_DETECTION_UNAVAILABLE");
            });
  }

  @Test
  void acceptsCompletionWhenEachStageUploadedItsOwnPhotoAsTheFinalImage() {
    DrawingSession house = uploadSession(100L, "htp-start-key");
    DrawingSession tree = uploadSession(101L, "htp-tree-key");
    DrawingSession person = uploadSession(102L, "htp-person-key");
    HtpAssessment assessment = completedAssessment(house, tree, person);
    DrawingAsset personPhoto = uploadedAsset(person, 603L);
    stubAuthorizedAssessment(assessment);
    stubStageFinalImages(
        List.of(uploadedAsset(house, 601L), uploadedAsset(tree, 602L), personPhoto));
    stubObjectAnalyses(List.of());
    stubCompletedConversations();
    stubReportCreation();

    HtpCompletionResponse response = service.complete(200L, "htp-complete-key");

    assertThat(response.status().name()).isEqualTo("ANALYZING");
    assertThat(response.reportId()).isEqualTo(901L);
    verify(stageFinalImageFinder).findAllBySession(List.of(house, tree, person));
    ArgumentCaptor<DrawingAnalysis> captor = ArgumentCaptor.captor();
    verify(drawingAnalysisRepository).saveAndFlush(captor.capture());
    assertThat(captor.getValue().getDrawingAsset()).isSameAs(personPhoto);
  }

  @Test
  void rejectsCompletionWithADistinctCodeWhenAStageDrawingIsStillInProgress() {
    DrawingSession house = persistedSession(100L, "htp-start-key");
    completeStep(house);
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            house,
            SERVER_TIME.minusHours(3),
            SERVER_TIME.plusHours(21),
            "htp-start-key");
    DrawingSession tree = persistedSession(101L, "htp-tree-key");
    assessment.advance(tree, SERVER_TIME.minusHours(2));
    completeStep(tree);
    DrawingSession person = persistedSession(102L, "htp-person-key");
    assessment.advance(person, SERVER_TIME.minusHours(1));
    ReflectionTestUtils.setField(assessment, "id", 200L);
    stubAuthorizedAssessment(assessment);

    assertThatThrownBy(() -> service.complete(200L, "htp-complete-key"))
        .isInstanceOf(BusinessException.class)
        .extracting(exception -> ((BusinessException) exception).getErrorCode())
        .isEqualTo(HtpErrorCode.HTP_STEP_DRAWING_NOT_COMPLETED);
  }

  @Test
  void rejectsCompletionWithADistinctCodeWhenAStageFinalImageIsMissing() {
    DrawingSession house = persistedSession(100L, "htp-start-key");
    DrawingSession tree = persistedSession(101L, "htp-tree-key");
    DrawingSession person = persistedSession(102L, "htp-person-key");
    HtpAssessment assessment = completedAssessment(house, tree, person);
    stubAuthorizedAssessment(assessment);
    stubStageFinalImages(List.of(finalAsset(house, 501L), finalAsset(tree, 502L)));

    assertThatThrownBy(() -> service.complete(200L, "htp-complete-key"))
        .isInstanceOf(BusinessException.class)
        .extracting(exception -> ((BusinessException) exception).getErrorCode())
        .isEqualTo(HtpErrorCode.HTP_FINAL_IMAGE_REQUIRED);
  }

  @Test
  void rejectsCompletionWithADistinctCodeWhenAStageConversationIsNotCompleted() {
    DrawingSession house = persistedSession(100L, "htp-start-key");
    DrawingSession tree = persistedSession(101L, "htp-tree-key");
    DrawingSession person = persistedSession(102L, "htp-person-key");
    HtpAssessment assessment = completedAssessment(house, tree, person);
    stubAuthorizedAssessment(assessment);
    stubStageFinalImages(
        List.of(finalAsset(house, 501L), finalAsset(tree, 502L), finalAsset(person, 503L)));
    given(conversationSessionRepository.findByDrawingSessionId(any()))
        .willAnswer(
            invocation -> {
              Long sessionId = invocation.getArgument(0, Long.class);
              return sessionId == 102L
                  ? Optional.of(
                      ConversationSession.start(
                          sessionId, "ELEMENTARY", 2, SERVER_TIME.minusMinutes(20)))
                  : Optional.of(completedConversation(sessionId));
            });

    assertThatThrownBy(() -> service.complete(200L, "htp-complete-key"))
        .isInstanceOf(BusinessException.class)
        .extracting(exception -> ((BusinessException) exception).getErrorCode())
        .isEqualTo(HtpErrorCode.HTP_CONVERSATION_NOT_COMPLETED);
  }

  @Test
  void rejectsAggregateCompletionBeforeAllThreeStepsAreReady() {
    DrawingSession house = persistedSession(100L, "htp-start-key");
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            house,
            SERVER_TIME.minusHours(1),
            SERVER_TIME.plusHours(23),
            "htp-start-key");
    ReflectionTestUtils.setField(assessment, "id", 200L);
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findDetailByIdForUpdate(200L))
        .willReturn(Optional.of(assessment));

    assertThatThrownBy(() -> service.complete(200L, "htp-complete-key"))
        .isInstanceOf(BusinessException.class);
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

  private DrawingSession uploadSession(Long id, String key) {
    DrawingSession session =
        DrawingSession.start(child, htpType, DrawingInputMethod.UPLOAD, SERVER_TIME, key);
    ReflectionTestUtils.setField(session, "id", id);
    return session;
  }

  private HtpAssessment completedAssessment(
      DrawingSession house, DrawingSession tree, DrawingSession person) {
    completeStep(house);
    HtpAssessment assessment =
        HtpAssessment.start(
            child,
            htpType,
            house,
            SERVER_TIME.minusHours(3),
            SERVER_TIME.plusHours(21),
            "htp-start-key");
    assessment.advance(tree, SERVER_TIME.minusHours(2));
    completeStep(tree);
    assessment.advance(person, SERVER_TIME.minusHours(1));
    completeStep(person);
    ReflectionTestUtils.setField(assessment, "id", 200L);
    return assessment;
  }

  private void stubAuthorizedAssessment(HtpAssessment assessment) {
    given(currentUserResolver.requireUserId()).willReturn(GUARDIAN_ID);
    given(htpAssessmentRepository.findDetailByIdForUpdate(200L))
        .willReturn(Optional.of(assessment));
  }

  private void stubStageFinalImages(List<DrawingAsset> assets) {
    Map<Long, DrawingAsset> images = new LinkedHashMap<>();
    assets.forEach(asset -> images.put(asset.getDrawingSession().getId(), asset));
    given(stageFinalImageFinder.findAllBySession(anyList())).willReturn(images);
  }

  private void stubObjectAnalyses(List<DrawingAnalysis> analyses) {
    given(
            drawingAnalysisRepository
                .findByDrawingSessionIdInAndScopeOrderByDrawingSessionIdAscRequestedAtDescIdDesc(
                    List.of(100L, 101L, 102L), DrawingAnalysisScope.FINAL))
        .willReturn(analyses);
  }

  private void stubCompletedConversations() {
    given(conversationSessionRepository.findByDrawingSessionId(any()))
        .willAnswer(
            invocation ->
                Optional.of(completedConversation(invocation.getArgument(0, Long.class))));
  }

  private void stubReportCreation() {
    given(drawingAnalysisRepository.saveAndFlush(any(DrawingAnalysis.class)))
        .willAnswer(
            invocation -> {
              DrawingAnalysis analysis = invocation.getArgument(0);
              ReflectionTestUtils.setField(analysis, "id", 900L);
              return analysis;
            });
    given(reportRepository.findFirstByDrawingSessionIdOrderByReportVersionDescIdDesc(102L))
        .willReturn(Optional.empty());
    given(reportRepository.saveAndFlush(any(Report.class)))
        .willAnswer(
            invocation -> {
              Report report = invocation.getArgument(0);
              ReflectionTestUtils.setField(report, "id", 901L);
              return report;
            });
  }

  private void completeStep(DrawingSession session) {
    session.startDrawingAnalysis();
    session.finishDrawingAnalysis();
    session.enterReflection();
    session.completeHtpStep(SERVER_TIME.minusMinutes(30));
  }

  private DrawingAsset finalAsset(DrawingSession session, Long id) {
    DrawingAsset asset =
        DrawingAsset.snapshot(
            session,
            DrawingAssetType.FINAL,
            1,
            "images/" + id + ".png",
            "image/png",
            1024,
            320,
            320,
            "a".repeat(64),
            SERVER_TIME.minusMinutes(40),
            SERVER_TIME.minusMinutes(40));
    ReflectionTestUtils.setField(asset, "id", id);
    return asset;
  }

  private DrawingAsset uploadedAsset(DrawingSession session, Long id) {
    DrawingAsset asset =
        DrawingAsset.uploaded(
            session,
            "images/" + id + ".jpg",
            "image/jpeg",
            2048,
            1440,
            1080,
            "b".repeat(64),
            SERVER_TIME.minusMinutes(45),
            SERVER_TIME.minusMinutes(44),
            "upload-key-" + id,
            "f".repeat(64),
            0,
            true);
    ReflectionTestUtils.setField(asset, "id", id);
    return asset;
  }

  private DrawingAnalysis failedObjectAnalysis(
      DrawingSession session, DrawingAsset asset, String requestId) {
    DrawingAnalysis analysis =
        DrawingAnalysis.processing(
            session,
            asset,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisType.OBJECT_DETECTION,
            requestId,
            SERVER_TIME.minusMinutes(35));
    analysis.fail("TIMEOUT", "그림 분석 처리에 실패했습니다.", SERVER_TIME.minusMinutes(34));
    return analysis;
  }

  private DrawingAnalysis successfulObjectAnalysis(
      DrawingSession session, DrawingAsset asset, String requestId) {
    DrawingAnalysis analysis =
        DrawingAnalysis.processing(
            session,
            asset,
            DrawingAnalysisScope.FINAL,
            DrawingAnalysisType.OBJECT_DETECTION,
            requestId,
            SERVER_TIME.minusMinutes(35));
    analysis.succeed("htp-yolo", "1.0", List.of(), SERVER_TIME.minusMinutes(34));
    return analysis;
  }

  private ConversationSession completedConversation(Long sessionId) {
    ConversationSession conversation =
        ConversationSession.start(sessionId, "ELEMENTARY", 2, SERVER_TIME.minusMinutes(20));
    conversation.complete(ConversationCompletionReason.CHILD_REQUEST, SERVER_TIME.minusMinutes(1));
    return conversation;
  }
}
