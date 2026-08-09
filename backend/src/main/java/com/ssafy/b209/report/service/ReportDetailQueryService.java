package com.ssafy.b209.report.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.auth.authorization.GuardianResourceAccessRepository;
import com.ssafy.b209.drawing.service.DrawingAssetFileUrlFactory;
import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.report.domain.ReportActivitySummaryView;
import com.ssafy.b209.report.domain.ReportChildView;
import com.ssafy.b209.report.domain.ReportConversationSummaryView;
import com.ssafy.b209.report.domain.ReportCrisisAlert;
import com.ssafy.b209.report.domain.ReportDetailView;
import com.ssafy.b209.report.domain.ReportDiaryEvidenceRef;
import com.ssafy.b209.report.domain.ReportDrawingAssetView;
import com.ssafy.b209.report.domain.ReportDrawingEmotionView;
import com.ssafy.b209.report.domain.ReportDrawingSessionView;
import com.ssafy.b209.report.domain.ReportDrawingTypeView;
import com.ssafy.b209.report.domain.ReportFeatureVisibility;
import com.ssafy.b209.report.domain.ReportInterpretationDisclosureState;
import com.ssafy.b209.report.domain.ReportKeyConversationView;
import com.ssafy.b209.report.domain.ReportMessageConfirmationView;
import com.ssafy.b209.report.domain.ReportObservedFeatureView;
import com.ssafy.b209.report.domain.ReportPublicInterpretation;
import com.ssafy.b209.report.domain.ReportSubject;
import com.ssafy.b209.report.domain.ReportSubjectObservation;
import com.ssafy.b209.report.dto.ReportActivityFactsResponse;
import com.ssafy.b209.report.dto.ReportChildExpressionResponse;
import com.ssafy.b209.report.dto.ReportConversationSummaryResponse;
import com.ssafy.b209.report.dto.ReportCrisisAlertResponse;
import com.ssafy.b209.report.dto.ReportCrisisResourceResponse;
import com.ssafy.b209.report.dto.ReportDetailResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryCaregiverQuestionResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryChildVoiceResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryDataQualityResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryDevelopmentalObservationResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryEvidenceRefResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryNarrativeStepResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiarySessionObservationResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryStorySnapshotResponse;
import com.ssafy.b209.report.dto.ReportDiaryInsightsResponse.DiaryUnknownItemResponse;
import com.ssafy.b209.report.dto.ReportDrawingResponse;
import com.ssafy.b209.report.dto.ReportDrawingSessionResponse;
import com.ssafy.b209.report.dto.ReportEvidenceItemResponse;
import com.ssafy.b209.report.dto.ReportExpertReviewResponse;
import com.ssafy.b209.report.dto.ReportObservedFeatureResponse;
import com.ssafy.b209.report.dto.ReportParentGuideResponse;
import com.ssafy.b209.report.dto.ReportPublicInterpretationResponse;
import com.ssafy.b209.report.dto.ReportQaPairResponse;
import com.ssafy.b209.report.dto.ReportReferenceResponse;
import com.ssafy.b209.report.dto.ReportSubjectResponse;
import com.ssafy.b209.report.dto.ReportUtteranceResponse;
import com.ssafy.b209.report.exception.ReportDetailErrorCode;
import com.ssafy.b209.report.repository.ReportActivityNoteViewRepository;
import com.ssafy.b209.report.repository.ReportActivitySummaryViewRepository;
import com.ssafy.b209.report.repository.ReportChildViewRepository;
import com.ssafy.b209.report.repository.ReportConversationSummaryViewRepository;
import com.ssafy.b209.report.repository.ReportCrisisAlertRepository;
import com.ssafy.b209.report.repository.ReportDetailViewRepository;
import com.ssafy.b209.report.repository.ReportDetectedObjectRow;
import com.ssafy.b209.report.repository.ReportDetectedObjectViewRepository;
import com.ssafy.b209.report.repository.ReportDiaryCaregiverQuestionRepository;
import com.ssafy.b209.report.repository.ReportDiaryChildVoiceRepository;
import com.ssafy.b209.report.repository.ReportDiaryDevelopmentSourceRepository;
import com.ssafy.b209.report.repository.ReportDiaryDevelopmentalObservationRepository;
import com.ssafy.b209.report.repository.ReportDiaryEvidenceRefRepository;
import com.ssafy.b209.report.repository.ReportDiaryInsightAlternativeRepository;
import com.ssafy.b209.report.repository.ReportDiaryInsightRepository;
import com.ssafy.b209.report.repository.ReportDiaryNarrativeStepRepository;
import com.ssafy.b209.report.repository.ReportDiarySessionObservationRepository;
import com.ssafy.b209.report.repository.ReportDiaryUnknownItemRepository;
import com.ssafy.b209.report.repository.ReportDrawingAssetViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingEmotionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingSessionViewRepository;
import com.ssafy.b209.report.repository.ReportDrawingTypeViewRepository;
import com.ssafy.b209.report.repository.ReportDrawnItemRepository;
import com.ssafy.b209.report.repository.ReportEvidenceItemRepository;
import com.ssafy.b209.report.repository.ReportFollowUpGuideViewRepository;
import com.ssafy.b209.report.repository.ReportHtpStepViewRepository;
import com.ssafy.b209.report.repository.ReportKeyConversationViewRepository;
import com.ssafy.b209.report.repository.ReportMessageConfirmationViewRepository;
import com.ssafy.b209.report.repository.ReportObservedFeatureViewRepository;
import com.ssafy.b209.report.repository.ReportParentGuideRepository;
import com.ssafy.b209.report.repository.ReportPublicInterpretationRepository;
import com.ssafy.b209.report.repository.ReportReferenceRepository;
import com.ssafy.b209.report.repository.ReportSubjectRepository;
import com.ssafy.b209.screening.dto.response.ScreeningSummaryResponse;
import com.ssafy.b209.screening.service.ScreeningRecordQueryService;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * REPORT-02 보호자용 관찰 리포트 상세 조회의 소유권 검증과 정규화된 리포트 데이터 조립을 담당하는 읽기 전용 서비스다.
 *
 * <p>리포트가 연결된 그림 활동 세션의 아동에 대한 보호자 접근 권한을 확인한 뒤, 리포트와 활동·대화·분석 하위 데이터를 읽기 전용 프로젝션으로 조립한다. 보호자 안전
 * 규칙에 따라 AI 추정 감정·확률, 위험도 점수, 내부 프롬프트·지표는 조회 대상에서 제외해 응답에 노출하지 않는다.
 *
 * <p><b>관찰 특징({@code report_observed_features})은 노출 범위로 나뉜다.</b> 이전에는 이 테이블을 통째로 조회 대상에서 제외했는데, 검토를
 * 통과시킬 상태값 자체가 없어 <b>모든 행이 {@code EXPERT_ONLY} 로만 저장됐기</b> 때문이다(운영 실측 97건 전부). 읽는 쪽도 쓰는 쪽도 없는 데이터를
 * 계속 만들고 있었다는 뜻이다. 지금은 AI 자체 검토를 통과한 리포트가 {@code REVIEWED_GUARDIAN} 항목을 남기므로 <b>그 항목만</b> 조회해 응답에
 * 싣는다. {@code EXPERT_ONLY} 는 여전히 조회하지 않는다 — FE 가 숨기는 것이 아니라 응답에 없어야 한다.
 */
@Service
@Transactional(readOnly = true)
public class ReportDetailQueryService {

  private static final String FINAL_ASSET_TYPE = "FINAL";
  private static final String THUMBNAIL_ASSET_TYPE = "THUMBNAIL";
  private static final String UPLOADED_ASSET_TYPE = "UPLOADED";
  private static final BigDecimal LEGACY_DETECTION_MIN_CONFIDENCE = new BigDecimal("0.50");

  /** 집·나무·사람 활동 코드다. AI 원문은 이 활동에서만 응답에 싣는다 (S15P11B209-980). */
  private static final String HTP_ACTIVITY_CODE = "HTP";

  private static final Logger log = LoggerFactory.getLogger(ReportDetailQueryService.class);

  private final GuardianResourceAccessRepository guardianAccessRepository;
  private final ReportDetailViewRepository reportRepository;
  private final ReportDrawingSessionViewRepository drawingSessionRepository;
  private final ReportDrawingTypeViewRepository drawingTypeRepository;
  private final ReportDrawingAssetViewRepository assetRepository;
  private final ReportDrawingEmotionViewRepository emotionRepository;
  private final ReportActivitySummaryViewRepository activitySummaryRepository;
  private final ReportActivityNoteViewRepository activityNoteRepository;
  private final ReportKeyConversationViewRepository keyConversationRepository;
  private final ReportFollowUpGuideViewRepository followUpGuideRepository;
  private final ReportDiaryInsightRepository diaryInsightRepository;
  private final ReportDiaryNarrativeStepRepository diaryNarrativeStepRepository;
  private final ReportDiaryChildVoiceRepository diaryChildVoiceRepository;
  private final ReportDiarySessionObservationRepository diarySessionObservationRepository;
  private final ReportDiaryCaregiverQuestionRepository diaryCaregiverQuestionRepository;
  private final ReportDiaryEvidenceRefRepository diaryEvidenceRefRepository;
  private final ReportDiaryInsightAlternativeRepository diaryAlternativeRepository;
  private final ReportDiaryDevelopmentalObservationRepository
      diaryDevelopmentalObservationRepository;
  private final ReportDiaryDevelopmentSourceRepository diaryDevelopmentSourceRepository;
  private final ReportDiaryUnknownItemRepository diaryUnknownItemRepository;
  private final ReportConversationSummaryViewRepository conversationSummaryRepository;
  private final ReportDetectedObjectViewRepository detectedObjectRepository;
  private final ReportDrawnItemRepository drawnItemRepository;
  private final ReportObservedFeatureViewRepository observedFeatureRepository;
  private final ReportPublicInterpretationRepository interpretationRepository;
  private final ReportEvidenceItemRepository evidenceItemRepository;
  private final ReportParentGuideRepository parentGuideRepository;
  private final ReportCrisisAlertRepository crisisAlertRepository;
  private final ReportMessageConfirmationViewRepository messageConfirmationRepository;
  private final ReportSubjectRepository subjectRepository;
  private final ReportReferenceRepository referenceRepository;
  private final ReportHtpStepViewRepository htpStepRepository;
  private final ReportChildViewRepository childRepository;
  private final DrawingAssetFileUrlFactory fileUrlFactory;
  private final ScreeningRecordQueryService screeningRecordQueryService;
  private final ObjectMapper objectMapper;

  /**
   * AI 원문을 응답에 실을지 여부다 (S15P11B209-980).
   *
   * <p>원문은 보호자 안전 선별을 거치지 않은 값이라 <b>끌 수 있어야 한다</b>. 지금은 화면 대조를 위해 기본으로 켜 둔다.
   */
  private final boolean aiRawReportExposed;

  /**
   * 리포트 상세 조회 Use Case 의존성을 생성한다.
   *
   * @param guardianAccessRepository 보호자-아동-그림 활동 접근 관계 조회 경계
   * @param reportRepository 리포트 헤더 조회 경계
   * @param drawingSessionRepository 그림 활동 세션 조회 경계
   * @param drawingTypeRepository 그림 활동 유형 조회 경계
   * @param assetRepository 그림 파일 URL 조회 경계
   * @param emotionRepository 아동 선택 감정 조회 경계
   * @param activitySummaryRepository 활동·대화 집계 요약 조회 경계
   * @param activityNoteRepository 활동 주의사항 조회 경계
   * @param keyConversationRepository 대표 대화 Snapshot 조회 경계
   * @param followUpGuideRepository 보호자 후속 안내 조회 경계
   * @param conversationSummaryRepository 대화 요약 대체 출처 조회 경계
   * @param detectedObjectRepository 과거 리포트의 탐지 객체명 폴백 조회 경계
   * @param drawnItemRepository 최신 AI 관찰 서술 기반 '그린 것' 조회 경계
   * @param observedFeatureRepository 보호자에게 열린 관찰 특징 조회 경계
   * @param subjectRepository 주제(집·나무·사람)별 관찰 스냅샷 조회 경계 (S15P11B209-960)
   * @param referenceRepository 리포트 참고 자료 조회 경계 (S15P11B209-960)
   * @param htpStepRepository 활동 수치가 여러 활동 합산인지 판정하는 HTP 단계 조회 경계 (S15P11B209-960)
   * @param childRepository 표지용 아동 표시명 조회 경계이며 별명만 읽는다 (S15P11B209-960)
   * @param fileUrlFactory 인증된 그림 파일 조회 URL 생성기
   * @param screeningRecordQueryService 아동의 검사 기록 요약 조회 경계
   * @param objectMapper 보관해 둔 AI 원문을 응답에 그대로 싣기 위한 Mapper (S15P11B209-980)
   * @param aiRawReportExposed AI 원문 노출 여부이며 기본은 켜짐
   */
  public ReportDetailQueryService(
      GuardianResourceAccessRepository guardianAccessRepository,
      ReportDetailViewRepository reportRepository,
      ReportDrawingSessionViewRepository drawingSessionRepository,
      ReportDrawingTypeViewRepository drawingTypeRepository,
      ReportDrawingAssetViewRepository assetRepository,
      ReportDrawingEmotionViewRepository emotionRepository,
      ReportActivitySummaryViewRepository activitySummaryRepository,
      ReportActivityNoteViewRepository activityNoteRepository,
      ReportKeyConversationViewRepository keyConversationRepository,
      ReportFollowUpGuideViewRepository followUpGuideRepository,
      ReportDiaryInsightRepository diaryInsightRepository,
      ReportDiaryNarrativeStepRepository diaryNarrativeStepRepository,
      ReportDiaryChildVoiceRepository diaryChildVoiceRepository,
      ReportDiarySessionObservationRepository diarySessionObservationRepository,
      ReportDiaryCaregiverQuestionRepository diaryCaregiverQuestionRepository,
      ReportDiaryEvidenceRefRepository diaryEvidenceRefRepository,
      ReportDiaryInsightAlternativeRepository diaryAlternativeRepository,
      ReportDiaryDevelopmentalObservationRepository diaryDevelopmentalObservationRepository,
      ReportDiaryDevelopmentSourceRepository diaryDevelopmentSourceRepository,
      ReportDiaryUnknownItemRepository diaryUnknownItemRepository,
      ReportConversationSummaryViewRepository conversationSummaryRepository,
      ReportDetectedObjectViewRepository detectedObjectRepository,
      ReportDrawnItemRepository drawnItemRepository,
      ReportObservedFeatureViewRepository observedFeatureRepository,
      ReportPublicInterpretationRepository interpretationRepository,
      ReportEvidenceItemRepository evidenceItemRepository,
      ReportParentGuideRepository parentGuideRepository,
      ReportCrisisAlertRepository crisisAlertRepository,
      ReportMessageConfirmationViewRepository messageConfirmationRepository,
      ReportSubjectRepository subjectRepository,
      ReportReferenceRepository referenceRepository,
      ReportHtpStepViewRepository htpStepRepository,
      ReportChildViewRepository childRepository,
      DrawingAssetFileUrlFactory fileUrlFactory,
      ScreeningRecordQueryService screeningRecordQueryService,
      ObjectMapper objectMapper,
      @Value("${app.report.ai-raw-report.exposed:true}") boolean aiRawReportExposed) {
    this.screeningRecordQueryService = screeningRecordQueryService;
    this.objectMapper = objectMapper;
    this.aiRawReportExposed = aiRawReportExposed;
    this.guardianAccessRepository = guardianAccessRepository;
    this.reportRepository = reportRepository;
    this.drawingSessionRepository = drawingSessionRepository;
    this.drawingTypeRepository = drawingTypeRepository;
    this.assetRepository = assetRepository;
    this.emotionRepository = emotionRepository;
    this.activitySummaryRepository = activitySummaryRepository;
    this.activityNoteRepository = activityNoteRepository;
    this.keyConversationRepository = keyConversationRepository;
    this.followUpGuideRepository = followUpGuideRepository;
    this.diaryInsightRepository = diaryInsightRepository;
    this.diaryNarrativeStepRepository = diaryNarrativeStepRepository;
    this.diaryChildVoiceRepository = diaryChildVoiceRepository;
    this.diarySessionObservationRepository = diarySessionObservationRepository;
    this.diaryCaregiverQuestionRepository = diaryCaregiverQuestionRepository;
    this.diaryEvidenceRefRepository = diaryEvidenceRefRepository;
    this.diaryAlternativeRepository = diaryAlternativeRepository;
    this.diaryDevelopmentalObservationRepository = diaryDevelopmentalObservationRepository;
    this.diaryDevelopmentSourceRepository = diaryDevelopmentSourceRepository;
    this.diaryUnknownItemRepository = diaryUnknownItemRepository;
    this.conversationSummaryRepository = conversationSummaryRepository;
    this.detectedObjectRepository = detectedObjectRepository;
    this.drawnItemRepository = drawnItemRepository;
    this.observedFeatureRepository = observedFeatureRepository;
    this.interpretationRepository = interpretationRepository;
    this.evidenceItemRepository = evidenceItemRepository;
    this.parentGuideRepository = parentGuideRepository;
    this.crisisAlertRepository = crisisAlertRepository;
    this.messageConfirmationRepository = messageConfirmationRepository;
    this.subjectRepository = subjectRepository;
    this.referenceRepository = referenceRepository;
    this.htpStepRepository = htpStepRepository;
    this.childRepository = childRepository;
    this.fileUrlFactory = fileUrlFactory;
  }

  /**
   * 보호자 접근 권한을 검증하고 리포트 상세 응답을 조립한다.
   *
   * <p>생성 중이거나 실패한 리포트는 하위 데이터가 비어 있어 각 섹션이 빈 목록·{@code null}로 조립되며, 별도 오류 없이 현재 상태를 그대로 반환한다.
   *
   * @param guardianUserId 인증에서 해석한 보호자 식별자
   * @param reportId URL 리포트 식별자
   * @return 보호자에게 노출 가능한 리포트 상세 응답
   * @throws BusinessException 리포트가 없거나 숨김이면 {@code REPORT_NOT_FOUND}, 보호자 접근 권한이 없으면 {@code
   *     REPORT_ACCESS_DENIED}
   */
  public ReportDetailResponse getReport(Long guardianUserId, Long reportId) {
    ReportDetailView report =
        reportRepository
            .findById(reportId)
            .orElseThrow(() -> new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND));
    if (report.isHidden()) {
      throw new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND);
    }
    if (!guardianAccessRepository.hasDrawingSessionAccess(
        guardianUserId, report.getDrawingSessionId())) {
      throw new BusinessException(ReportDetailErrorCode.REPORT_ACCESS_DENIED);
    }

    ReportDrawingSessionView session =
        drawingSessionRepository
            .findById(report.getDrawingSessionId())
            .orElseThrow(() -> new BusinessException(ReportDetailErrorCode.REPORT_NOT_FOUND));

    // 공개 카드를 한 번만 읽어 응답 배열과 주제별 참조가 같은 목록을 보게 한다. 따로 두 번 읽으면
    //   그 사이 정렬이 어긋날 때 interpretationRefs 가 조용히 다른 카드를 가리킨다(875 §5-1).
    List<ReportPublicInterpretation> publishedCards =
        interpretationRepository.findByReportIdAndDisclosureStateOrderByDisplayOrderAsc(
            report.getId(), ReportInterpretationDisclosureState.PUBLISHED);
    Map<Long, Integer> interpretationIndexById = new LinkedHashMap<>();
    for (int index = 0; index < publishedCards.size(); index++) {
      interpretationIndexById.put(publishedCards.get(index).getId(), index);
    }

    boolean aggregatedHtp =
        htpStepRepository.countStepsSharingAssessment(report.getDrawingSessionId()) > 1;

    return new ReportDetailResponse(
        report.getId(),
        report.getReportVersion(),
        report.getStatus().name(),
        buildDrawingSession(session),
        buildDrawing(session.getId()),
        buildChildExpression(report, session),
        buildObservedFeatures(report.getId()),
        buildActivityFacts(report, aggregatedHtp),
        buildConversationSummary(report),
        buildGuardianConversationGuide(report.getId()),
        splitLimitations(report.getLimitationsText()),
        ReportExpertReviewResponse.notRequested(),
        report.getCreatedAt(),
        ReportDetailResponse.NON_DIAGNOSTIC_NOTICE,
        buildPublicInterpretations(publishedCards),
        buildEvidenceItems(report.getId(), publishedCards),
        buildSubjectReports(report.getId(), interpretationIndexById),
        buildParentGuides(report.getId()),
        buildCrisisAlert(report.getId()),
        buildReferences(report.getId()),
        resolveActivityType(session),
        resolveChildDisplayName(session),
        resolveAiRawReport(report, resolveActivityType(session)),
        buildDiaryInsights(report.getId()),
        buildScreeningSummary(session));
  }

  /**
   * 이 아이의 검사 기록 요약을 만든다.
   *
   * <p>그림일기 관찰과 <b>자리를 나눠</b> 내보낸다. 앱이 만든 관찰과 보호자가 다른 곳에서 받아 온 검사 결과는 근거의 성격이 전혀 다르고, 한 덩어리로 보이면
   * 보호자는 앱이 검사를 해 줬다고 읽는다. 기록이 없어도 요약은 나간다 — 침묵이 곧 '앱이 선별을 해 준다'는 오해를 남긴다.
   *
   * <p>보호자 권한은 리포트 상세 진입에서 이미 확인했으므로 여기서 다시 보지 않는다.
   *
   * @param session 리포트가 가리키는 그림 활동 세션
   * @return 검사 기록 요약이며 아동을 알 수 없으면 {@code null}
   */
  private ScreeningSummaryResponse buildScreeningSummary(ReportDrawingSessionView session) {
    Long childId = session.getChildId();
    return childId == null ? null : screeningRecordQueryService.summarize(childId);
  }

  /**
   * 집·나무·사람 활동이면 보관해 둔 AI 응답 원문을 그대로 실어 준다 (S15P11B209-980).
   *
   * <p>목적은 <b>고정 스키마가 무엇을 버리는지 나란히 보는 것</b>이다. 그래서 스키마 검증도 필터도 하지 않는다 — 줄이면 이 필드를 두는 이유가 없어진다.
   *
   * <p>⚠️ <b>이 값만은 보호자 안전 선별을 거치지 않는다.</b> 응답의 다른 필드는 {@code EXPERT_ONLY} 관찰, 위기 심각도, AI 추정 감정,
   * 신뢰도를 의도적으로 걸러 내는데(CLAUDE.md 9절, 계약 §4) 원문에는 그것들이 들어 있다. 실사용자 공개 전에 <b>노출 대상을 좁히거나 이 필드를 제거해야
   * 한다</b> — 지금은 화면 대조를 위해 켜 둔 상태이고, {@code app.report.ai-raw-report.exposed=false} 로 끌 수 있다.
   *
   * <p>집·나무·사람이 아닌 활동은 지시대로 아무것도 바꾸지 않는다. 원문 보관 이전에 만든 리포트는 비어 있다 — 오류가 아니다.
   *
   * @param report 리포트 읽기 모델
   * @param activityType 활동 유형 코드
   * @return 원문 JSON 이며 대상이 아니거나 보관하지 않았거나 읽을 수 없으면 {@code null}
   */
  private JsonNode resolveAiRawReport(ReportDetailView report, String activityType) {
    if (!aiRawReportExposed || !HTP_ACTIVITY_CODE.equalsIgnoreCase(activityType)) {
      return null;
    }
    String rawJson = report.getAiRawReport();
    if (rawJson == null || rawJson.isBlank()) {
      return null;
    }
    try {
      return objectMapper.readTree(rawJson);
    } catch (JsonProcessingException exception) {
      // 원문이 JSON 이 아니면 실을 방법이 없다. 리포트 조회 자체는 성공시킨다 — 원문 한 덩어리
      //   때문에 보호자가 리포트를 못 보는 것이 더 나쁘다. 원문은 로그에도 남기지 않는다.
      log.warn("리포트 AI 원문을 JSON 으로 읽지 못했습니다. reportId={}", report.getId());
      return null;
    }
  }

  /**
   * 주제(집·나무·사람)별 관찰 묶음을 조립한다 (875 §5).
   *
   * <p>저장된 스냅샷을 그대로 읽는다 — 계약이 "리포트 상세의 스냅샷을 우선 사용(별도 재조립 금지)"이라 조회할 때마다 대화 로그를 다시 훑지 않는다. 순서는 저장
   * 시점에 {@code HOUSE → TREE → PERSON}으로 굳혀 뒀고 조회도 그 순서로 읽는다.
   *
   * <p>{@code interpretationRefs}는 <b>저장된 숫자가 아니라 지금 공개된 카드 목록에서의 위치</b>다. 저장은 카드 행을 FK 로 묶어 두고
   * 인덱스는 여기서 계산한다 — 그래야 카드 하나가 빠져도 참조가 다른 카드로 밀리지 않는다(875 §5-1).
   *
   * @param reportId 리포트 식별자
   * @param interpretationIndexById 공개 카드 식별자를 응답 배열 인덱스로 옮기는 표
   * @return 계약 순서대로 정렬된 주제별 관찰 목록이며 주제가 없으면 빈 목록
   */
  private List<ReportSubjectResponse> buildSubjectReports(
      Long reportId, Map<Long, Integer> interpretationIndexById) {
    List<ReportSubjectResponse> subjects = new ArrayList<>();
    for (ReportSubject subject : subjectRepository.findByReportIdOrderByDisplayOrderAsc(reportId)) {
      List<String> observations =
          subject.getObservations().stream()
              .map(ReportSubjectObservation::getObservationText)
              .filter(text -> text != null && !text.isBlank())
              .toList();
      List<ReportQaPairResponse> qaPairs =
          subject.getQaPairs().stream()
              .map(
                  pair ->
                      new ReportQaPairResponse(
                          pair.getQuestionText(),
                          pair.getAnswerText(),
                          pair.getAnswerState(),
                          pair.getInputType(),
                          // 미확정 음성은 문답 표시에는 남긴다 — 아이 말을 지우지 않고
                          //   "확인해 주세요"를 함께 보여 준다(875 §6-1).
                          pair.isSttNeedsConfirmation(),
                          pair.isRepresentative()))
              .toList();
      List<Integer> interpretationRefs =
          subject.getInterpretations().stream()
              .map(link -> interpretationIndexById.get(link.getInterpretation().getId()))
              .filter(index -> index != null)
              .toList();
      subjects.add(
          new ReportSubjectResponse(
              subject.getSubjectType(),
              resolveFinalImageUrl(subject.getDrawingSessionId()),
              observations,
              qaPairs,
              interpretationRefs));
    }
    return subjects;
  }

  /**
   * 리포트가 참조한 전문 자료 출처를 담는다 (875 §9).
   *
   * <p>출처 표시는 라이선스 의무(KOGL-1)라 저장된 것을 빠뜨리지 않는다. {@code url}은 자체 저작 자료가 많아 {@code null}일 수 있다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서 참고 자료 목록
   */
  private List<ReportReferenceResponse> buildReferences(Long reportId) {
    return referenceRepository.findByReportIdOrderByDisplayOrderAsc(reportId).stream()
        .map(reference -> new ReportReferenceResponse(reference.getTitle(), reference.getUrl()))
        .toList();
  }

  /**
   * 활동 유형 코드를 돌려준다 (875 §2 {@code activityType}).
   *
   * @param session 리포트가 가리키는 그림 활동 세션
   * @return 활동 유형 코드이며 유형을 알 수 없으면 {@code null}
   */
  private String resolveActivityType(ReportDrawingSessionView session) {
    ReportDrawingTypeView drawingType =
        drawingTypeRepository.findById(session.getDrawingTypeId()).orElse(null);
    return drawingType == null ? null : drawingType.getCode();
  }

  /**
   * 리포트 표지에 쓸 아동 표시명을 돌려준다 (875 §2 {@code childDisplayName}).
   *
   * <p><b>표시명(별명)만 쓴다.</b> 생년월일 같은 다른 아동 정보는 이 응답에 담지 않는다 — 조회 자체를 {@link ReportChildView}로 좁혀 뒀다.
   * 삭제된 아동은 {@code null}이다.
   *
   * @param session 리포트가 가리키는 그림 활동 세션
   * @return 아동 표시명이며 없거나 삭제됐으면 {@code null}
   */
  private String resolveChildDisplayName(ReportDrawingSessionView session) {
    if (session.getChildId() == null) {
      return null;
    }
    return childRepository
        .findById(session.getChildId())
        .map(ReportChildView::displayName)
        .orElse(null);
  }

  private ReportDrawingSessionResponse buildDrawingSession(ReportDrawingSessionView session) {
    ReportDrawingTypeView drawingType =
        drawingTypeRepository.findById(session.getDrawingTypeId()).orElse(null);
    return new ReportDrawingSessionResponse(
        session.getId(),
        session.getChildId(),
        drawingType == null ? null : drawingType.getCode(),
        drawingType == null ? null : drawingType.getName(),
        session.getTitle(),
        session.getInputMethod(),
        session.getStartedAt(),
        session.getCompletedAt(),
        session.durationMs());
  }

  /**
   * 리포트 상세에 표시할 그림 URL을 확정한다.
   *
   * <p>사진 업로드로 진행한 세션은 최종 그림을 다시 그리지 않아 업로드 원본만 남으므로, {@code FINAL}이 없으면 {@code UPLOADED}를 최종 그림으로
   * 인정한다. 이 폴백이 없으면 업로드 세션 리포트의 그림 자리가 빈다. 목록·미리보기의 같은 규칙은 {@code SessionPreviewImageUrlFinder}가
   * 담당한다.
   *
   * @param drawingSessionId 리포트가 가리키는 그림 활동 세션 식별자
   * @return 최종 그림·미리보기 URL이며 그림 파일이 없으면 두 항목 모두 {@code null}
   */
  private ReportDrawingResponse buildDrawing(Long drawingSessionId) {
    Map<String, ReportDrawingAssetView> latestByType = latestAssetsByType(drawingSessionId);
    String finalImageUrl = finalImageUrlOf(latestByType);
    String thumbnailUrl = urlOf(latestByType.get(THUMBNAIL_ASSET_TYPE));
    return new ReportDrawingResponse(
        finalImageUrl, thumbnailUrl == null ? finalImageUrl : thumbnailUrl);
  }

  /**
   * 주제별 그림 한 장의 완성 이미지 URL 을 확정한다 (875 §5 {@code imageUrl}).
   *
   * <p>상세 화면의 대표 그림과 <b>같은 규칙</b>을 쓴다 — 업로드 세션은 {@code FINAL} 자산이 없어 {@code UPLOADED}가 완성 그림이다. 저장할
   * 때 URL 문자열을 굳히지 않고 세션만 담아 둔 이유가 이것이다: 조회 시점에 발급해야 인증 경로가 바뀌어도 링크가 살아 있다.
   *
   * @param drawingSessionId 주제의 그림 활동 세션 식별자이며 없으면 {@code null}
   * @return 완성 그림 조회 URL 이며 그림이 없으면 {@code null}
   */
  private String resolveFinalImageUrl(Long drawingSessionId) {
    if (drawingSessionId == null) {
      return null;
    }
    return finalImageUrlOf(latestAssetsByType(drawingSessionId));
  }

  private Map<String, ReportDrawingAssetView> latestAssetsByType(Long drawingSessionId) {
    List<ReportDrawingAssetView> assets =
        assetRepository.findByDrawingSessionIdAndAssetTypeInOrderByAssetVersionAsc(
            drawingSessionId, List.of(FINAL_ASSET_TYPE, THUMBNAIL_ASSET_TYPE, UPLOADED_ASSET_TYPE));
    Map<String, ReportDrawingAssetView> latestByType = new LinkedHashMap<>();
    for (ReportDrawingAssetView asset : assets) {
      ReportDrawingAssetView current = latestByType.get(asset.getAssetType());
      if (current == null || asset.getAssetVersion() >= current.getAssetVersion()) {
        latestByType.put(asset.getAssetType(), asset);
      }
    }
    return latestByType;
  }

  private String finalImageUrlOf(Map<String, ReportDrawingAssetView> latestByType) {
    String finalImageUrl = urlOf(latestByType.get(FINAL_ASSET_TYPE));
    return finalImageUrl == null ? urlOf(latestByType.get(UPLOADED_ASSET_TYPE)) : finalImageUrl;
  }

  private String urlOf(ReportDrawingAssetView asset) {
    return asset == null ? null : fileUrlFactory.create(asset.getId());
  }

  private ReportChildExpressionResponse buildChildExpression(
      ReportDetailView report, ReportDrawingSessionView session) {
    List<String> selectedEmotions = new ArrayList<>();
    for (ReportDrawingEmotionView emotion :
        emotionRepository.findByDrawingSessionIdOrderBySelectionOrderAsc(session.getId())) {
      selectedEmotions.add(emotion.getEmotionCode());
    }

    List<ReportKeyConversationView> conversations =
        keyConversationRepository.findByReportIdOrderByDisplayOrderAsc(report.getId());
    // 음성 인식 확인 필요 여부는 원 메시지에만 있다. 종전에는 리터럴 false 를 넘겨
    // "미확정 발화는 대표 발화에서 제외한다"는 규칙(계약 §4-4)이 조용히 무효였다.
    Set<Long> needsConfirmation = loadMessagesNeedingConfirmation(conversations);
    List<ReportUtteranceResponse> utterances = new ArrayList<>();
    for (ReportKeyConversationView conversation : conversations) {
      boolean unconfirmed =
          conversation.getAnswerMessageId() != null
              && needsConfirmation.contains(conversation.getAnswerMessageId());
      if (unconfirmed) {
        // 문답 표시에는 남기지만 대표 발화에서는 제외한다 — 아이 말을 지우는 것이 아니라
        // 확인되지 않은 인식 결과를 보호자 인용으로 쓰지 않는 것이다.
        continue;
      }
      utterances.add(
          new ReportUtteranceResponse(
              conversation.getAnswerMessageId(),
              conversation.getAnswerText(),
              deriveSource(conversation.getAnswerType()),
              false));
    }
    return new ReportChildExpressionResponse(
        selectedEmotions, session.getExpressedEmotionText(), utterances);
  }

  /**
   * 보호자에게 열린 관찰 특징만 조회해 응답 형태로 옮긴다.
   *
   * <p>조회 자체를 {@link ReportFeatureVisibility#REVIEWED_GUARDIAN} 로 좁힌다. {@code EXPERT_ONLY} 행은 읽지도
   * 않으므로 필터를 빠뜨려 새어 나갈 경로가 없다.
   *
   * <p>{@code description} 이 비어 있는 행은 담지 않는다 — 제목만 있고 내용이 없는 카드는 보호자 화면에서 빈 칸으로 보인다. 저장 시점에 비어 있을 수
   * 없는 값이지만(도메인 불변식) 읽는 쪽에서도 확인한다.
   *
   * @param reportId 리포트 식별자
   * @return 노출 순서대로 정렬된 관찰 특징 목록이며 열린 항목이 없으면 빈 목록
   */
  private List<ReportObservedFeatureResponse> buildObservedFeatures(Long reportId) {
    List<ReportObservedFeatureResponse> features = new ArrayList<>();
    for (ReportObservedFeatureView feature :
        observedFeatureRepository.findByReportIdAndVisibilityScopeOrderByDisplayOrderAsc(
            reportId, ReportFeatureVisibility.REVIEWED_GUARDIAN)) {
      String description = feature.getDescription();
      if (description == null || description.isBlank()) {
        continue;
      }
      features.add(
          new ReportObservedFeatureResponse(
              feature.getTitle(), description, feature.getEvidenceSummary()));
    }
    return features;
  }

  private String deriveSource(String answerType) {
    if (answerType != null && answerType.toUpperCase().contains("VOICE")) {
      return "STT";
    }
    return "TEXT";
  }

  /**
   * 객관 활동 수치를 담는다 (875 §8).
   *
   * @param report 리포트 헤더
   * @param aggregatedHtp 여러 활동을 합친 기록인지 여부다. {@code true}면 화면이 "집·나무·사람 세 활동을 합친 기록입니다"를 덧붙인다 — 합산
   *     사실을 밝히지 않으면 보호자가 한 장을 그리는 데 걸린 시간으로 읽는다
   * @return 활동 수치 응답
   */
  private ReportActivityFactsResponse buildActivityFacts(
      ReportDetailView report, boolean aggregatedHtp) {
    ReportActivitySummaryView summary =
        activitySummaryRepository.findById(report.getId()).orElse(null);

    List<String> notes = new ArrayList<>();
    activityNoteRepository
        .findByReportIdOrderByDisplayOrderAsc(report.getId())
        .forEach(note -> notes.add(note.getNoteText()));

    Long drawingDurationMs = summary == null ? null : summary.getDrawingDurationMs();
    return new ReportActivityFactsResponse(
        buildDetectedObjects(report),
        drawingDurationMs,
        summary == null ? null : summary.getPauseCount(),
        summary == null ? null : summary.getEraseCount(),
        summary != null && summary.isPressureAvailable(),
        notes,
        // 875 는 초 단위를 쓴다. 기존 밀리초 필드는 지우지 않는다 — FE 가 두 형태를 모두 읽는다.
        ReportActivityFactsResponse.toSeconds(drawingDurationMs),
        ReportActivityFactsResponse.toSeconds(drawingDurationMs),
        null,
        summary == null ? null : summary.getConversationQuestionCount(),
        summary == null ? null : summary.getConversationAnsweredCount(),
        summary == null ? null : summary.getConversationSkippedCount(),
        null,
        null,
        false,
        aggregatedHtp);
  }

  /** 최신 리포트는 관찰 서술 항목을, 이전 리포트는 신뢰도 보정된 탐지 라벨만 사용한다. */
  private List<String> buildDetectedObjects(ReportDetailView report) {
    if (report.hasDrawnItems()) {
      return drawnItemRepository.findByReportIdOrderByDisplayOrderAsc(report.getId()).stream()
          .map(item -> item.getName())
          .filter(name -> name != null && !name.isBlank())
          .toList();
    }
    return buildLegacyDetectedObjects(report.getDrawingSessionId());
  }

  /**
   * 기존 리포트의 YOLO 라벨을 0.50 이상으로 제한해 반환한다.
   *
   * <p>조회 결과는 이미 주제 순서와 세션별 분석 최신순으로 정렬돼 있어, 세션마다 처음 만난 분석의 행만 남기면 세션당 최신 한 건이 된다. 탐지 결과가 없는 세션은 행이
   * 없어 자연히 건너뛴다.
   */
  private List<String> buildLegacyDetectedObjects(Long drawingSessionId) {
    List<String> detectedObjects = new ArrayList<>();
    Map<Long, Long> latestAnalysisBySession = new HashMap<>();
    for (ReportDetectedObjectRow row :
        detectedObjectRepository.findActivityDetectedObjects(drawingSessionId)) {
      Long latestAnalysisId =
          latestAnalysisBySession.computeIfAbsent(row.drawingSessionId(), key -> row.analysisId());
      if (!latestAnalysisId.equals(row.analysisId())) {
        continue;
      }
      String name = row.objectName();
      if (name != null
          && !name.isBlank()
          && row.confidenceScore() != null
          && row.confidenceScore().compareTo(LEGACY_DETECTION_MIN_CONFIDENCE) >= 0) {
        detectedObjects.add(name);
      }
    }
    return detectedObjects;
  }

  /**
   * 공개 판정을 통과한 경향 해석만 노출 순서대로 담는다 (계약 §4-1·§4-3).
   *
   * <p>제외·강등 카드는 저장돼 있어도 담지 않는다. 그리고 {@code resolveVisibility()}·{@code expertReviewed} 경로를 타지 않는다
   * — 그 경로는 전문가 검토 전 항목을 전부 EXPERT_ONLY 로 강등하고 검토 상태 전이가 없어 항상 미검토이므로, 통과한 카드까지 숨긴다(계약 §4-2 결정 1).
   *
   * <p><b>배열 순서를 여기서 다시 정렬하지 않는다.</b> 주제별 관찰의 {@code interpretationRefs}가 이 배열의 인덱스를 가리키므로, 순서를 바꾸면
   * 참조가 조용히 다른 카드를 가리킨다(875 §5-1).
   *
   * @param publishedCards 노출 순서대로 읽어 둔 공개 카드 목록
   * @return 공개 카드 목록이며 통과분이 없으면 빈 목록
   */
  private List<ReportPublicInterpretationResponse> buildPublicInterpretations(
      List<ReportPublicInterpretation> publishedCards) {
    return publishedCards.stream()
        .map(
            card ->
                new ReportPublicInterpretationResponse(
                    card.getCategory().name(),
                    card.getTitle(),
                    card.getTendencyText(),
                    card.getScopeText(),
                    card.getHomeObservationGuide(),
                    card.getEvidences().stream()
                        .map(link -> link.getEvidenceItem().getEvidenceNumber())
                        .toList(),
                    // 등급이 없는 카드(V43 이전 저장분·AI 미전송·해석 실패)는 null 로 내보낸다. 여기서
                    // 기본값을 채우면 계산된 적 없는 등급이 보호자 화면에 사실처럼 뜬다 (S15P11B209-982).
                    card.getConfidence() == null ? null : card.getConfidence().name()))
        .toList();
  }

  /**
   * 카드가 참조하는 근거 풀을 담는다 (875 §4).
   *
   * <p>원본 참조({@code sourceRef})는 담지 않는다 — 서버가 발급한 행 식별자를 보호자 응답으로 내보낼 이유가 없다.
   *
   * <p><b>공개된 카드가 실제로 참조하는 근거만 담는다</b> (S15P11B209-985). 근거는 공개 여부와 무관하게 <i>저장</i>된다 — 미공개·강등 판정의
   * 사유를 나중에 되짚어야 하기 때문이고, 그 저장 정책은 그대로 둔다. 그러나 <b>응답은 다르다.</b> 예전에는 리포트의 근거 행을 전부 실어, 안전 검증기가 "내보내지
   * 말자"고 판정한 카드의 근거 — 대개 <b>아이 발화 인용</b>이다 — 까지 보호자 기기로 전송됐다.
   *
   * <p>앱이 이 배열을 조회용 맵으로만 써서 화면에는 뜨지 않았지만, 그것은 <b>클라이언트 구현에 기댄 방어</b>다. 앱이 바뀌면 조용히 노출된다. 아동 민감정보는
   * 필요한 만큼만 전송한다(CLAUDE.md 9절).
   *
   * <p>거르는 것이 안전한 이유: 카드의 {@code evidenceRefs}와 이 배열의 {@code evidenceId}는 <b>둘 다 {@code
   * evidenceNumber} 값</b>이다. 배열 인덱스가 아니므로 목록에서 일부를 빼도 참조가 다른 근거를 가리키지 않는다 (배열 인덱스였다면 960 이 겪은 어긋남이
   * 그대로 재발했을 것이다).
   *
   * @param reportId 리포트 식별자
   * @param publishedCards 보호자 응답에 실리는 공개 카드 목록
   * @return 공개 카드가 참조하는 근거만, 근거 번호 순서로
   */
  private List<ReportEvidenceItemResponse> buildEvidenceItems(
      Long reportId, List<ReportPublicInterpretation> publishedCards) {
    Set<Integer> referenced =
        publishedCards.stream()
            .flatMap(card -> card.getEvidences().stream())
            .map(link -> link.getEvidenceItem().getEvidenceNumber())
            .collect(Collectors.toSet());
    if (referenced.isEmpty()) {
      return List.of();
    }
    return evidenceItemRepository.findByReportIdOrderByEvidenceNumberAsc(reportId).stream()
        .filter(item -> referenced.contains(item.getEvidenceNumber()))
        .map(
            item ->
                new ReportEvidenceItemResponse(
                    item.getEvidenceNumber(), item.getSourceType().name(), item.getText()))
        .toList();
  }

  /**
   * 보호자 가이드를 유형별로 묶는다 (875 §7).
   *
   * <p>저장은 문장 단위 행이고 응답은 유형별 문장 목록이다. 유형 순서와 유형 안의 순서를 모두 보존한다.
   *
   * @param reportId 리포트 식별자
   * @return 유형별 가이드 목록
   */
  private List<ReportParentGuideResponse> buildParentGuides(Long reportId) {
    Map<String, List<String>> byType = new LinkedHashMap<>();
    parentGuideRepository
        .findByReportIdOrderByGuideTypeAscDisplayOrderAsc(reportId)
        .forEach(
            guide ->
                byType
                    .computeIfAbsent(guide.getGuideType().name(), key -> new ArrayList<>())
                    .add(guide.getGuidance()));
    return byType.entrySet().stream()
        .map(entry -> new ReportParentGuideResponse(entry.getKey(), entry.getValue()))
        .toList();
  }

  /**
   * 위기 대응 안내를 담는다 (875 §7-1).
   *
   * <p>{@code null}이 곧 위기 신호 없음이다. {@code ABUSE_DISCLOSURE}는 저장 단계에서 막혀 있어 여기로 올 수 없다.
   *
   * @param reportId 리포트 식별자
   * @return 위기 안내이며 없으면 {@code null}
   */
  private ReportCrisisAlertResponse buildCrisisAlert(Long reportId) {
    ReportCrisisAlert alert = crisisAlertRepository.findById(reportId).orElse(null);
    if (alert == null) {
      return null;
    }
    return new ReportCrisisAlertResponse(
        alert.getReasonCode(),
        alert.getSeverity(),
        alert.getTitle(),
        alert.getMessage(),
        alert.getSteps().stream().map(step -> step.getStepText()).toList(),
        alert.getResources().stream()
            .map(
                resource ->
                    new ReportCrisisResourceResponse(
                        resource.getResourceName(), resource.getContact(), resource.getNote()))
            .toList());
  }

  /**
   * 대표 대화의 답변 메시지 중 음성 인식 확인이 필요한 식별자를 배치로 읽는다.
   *
   * @param conversations 대표 대화 목록
   * @return 확인이 필요한 답변 메시지 식별자 집합
   */
  private Set<Long> loadMessagesNeedingConfirmation(List<ReportKeyConversationView> conversations) {
    List<Long> answerIds =
        conversations.stream()
            .map(ReportKeyConversationView::getAnswerMessageId)
            .filter(id -> id != null)
            .distinct()
            .toList();
    if (answerIds.isEmpty()) {
      return Set.of();
    }
    return messageConfirmationRepository.findByIdIn(answerIds).stream()
        .filter(ReportMessageConfirmationView::isNeedsGuardianConfirmation)
        .map(ReportMessageConfirmationView::getId)
        .collect(java.util.stream.Collectors.toSet());
  }

  private ReportConversationSummaryResponse buildConversationSummary(ReportDetailView report) {
    ReportActivitySummaryView summary =
        activitySummaryRepository.findById(report.getId()).orElse(null);
    String summaryText = summary == null ? null : summary.getConversationSummary();
    if (summaryText == null || summaryText.isBlank()) {
      summaryText = fallbackSummaryText(report.getAnalysisId());
    }
    return new ReportConversationSummaryResponse(
        summary == null ? null : summary.getConversationQuestionCount(),
        summary == null ? null : summary.getConversationAnsweredCount(),
        summary == null ? null : summary.getConversationSkippedCount(),
        summaryText);
  }

  private String fallbackSummaryText(Long analysisId) {
    List<ReportConversationSummaryView> summaries =
        conversationSummaryRepository.findByAnalysisIdOrderByIdAsc(analysisId);
    for (ReportConversationSummaryView summary : summaries) {
      if (summary.getSummaryText() != null && !summary.getSummaryText().isBlank()) {
        return summary.getSummaryText();
      }
    }
    return null;
  }

  private List<String> buildGuardianConversationGuide(Long reportId) {
    List<String> guides = new ArrayList<>();
    followUpGuideRepository
        .findByReportIdOrderByDisplayOrderAsc(reportId)
        .forEach(guide -> guides.add(guide.getGuidance()));
    return guides;
  }

  private List<String> splitLimitations(String limitationsText) {
    List<String> limitations = new ArrayList<>();
    if (limitationsText == null) {
      return limitations;
    }
    for (String line : limitationsText.split("\\R")) {
      String trimmed = line.strip();
      if (!trimmed.isEmpty()) {
        limitations.add(trimmed);
      }
    }
    return limitations;
  }

  /**
   * 그림일기 V2 구조화 결과를 만든다. 저장된 것이 없으면 {@code null}을 돌려준다.
   *
   * <p>{@code null}과 빈 껍데기를 가르는 것이 이 메서드의 일이다 — 앱은 이 값의 유무로 V2 화면을 열지 정한다. HTP 리포트와, 근거가 부족해 AI 가
   * 구조화를 포기한 그림일기는 둘 다 저장된 행이 없어 여기서 {@code null}이 나간다.
   */
  private ReportDiaryInsightsResponse buildDiaryInsights(Long reportId) {
    return diaryInsightRepository
        .findById(reportId)
        .map(
            insight -> {
              Map<String, List<DiaryEvidenceRefResponse>> refs = loadDiaryEvidenceRefs(reportId);
              Map<Integer, List<String>> alternatives = loadDiaryAlternatives(reportId);
              return new ReportDiaryInsightsResponse(
                  new DiaryStorySnapshotResponse(
                      insight.getHeadline(),
                      insight.getSummary(),
                      insight.getRealityStatus(),
                      insight.getTimeScope(),
                      insight.getMainEvent(),
                      refs.getOrDefault(
                          diaryRefKey(ReportDiaryEvidenceRef.OWNER_STORY_SNAPSHOT, 0), List.of())),
                  diaryNarrativeStepRepository
                      .findByReportIdOrderByDisplayOrderAsc(reportId)
                      .stream()
                      .map(
                          step ->
                              new DiaryNarrativeStepResponse(
                                  step.getStepType(),
                                  step.getText(),
                                  refs.getOrDefault(
                                      diaryRefKey(
                                          ReportDiaryEvidenceRef.OWNER_NARRATIVE_STEP,
                                          step.getDisplayOrder()),
                                      List.of())))
                      .toList(),
                  diaryChildVoiceRepository.findByReportIdOrderByDisplayOrderAsc(reportId).stream()
                      .map(
                          voice ->
                              new DiaryChildVoiceResponse(
                                  voice.getText(),
                                  voice.getElicitationType(),
                                  voice.getAnswerType(),
                                  voice.getSourceRefId() == null
                                      ? null
                                      : new DiaryEvidenceRefResponse(
                                          voice.getSourceRefKind(), voice.getSourceRefId()),
                                  voice.isSttNeedsConfirmation()))
                      .toList(),
                  diarySessionObservationRepository
                      .findByReportIdOrderByDisplayOrderAsc(reportId)
                      .stream()
                      .map(
                          observation ->
                              new DiarySessionObservationResponse(
                                  observation.getObservationCode(),
                                  observation.getInsightType(),
                                  observation.getDomain(),
                                  observation.getTitle(),
                                  observation.getDescription(),
                                  observation.getHypothesis(),
                                  alternatives.getOrDefault(
                                      observation.getDisplayOrder(), List.of()),
                                  observation.getClarificationQuestion(),
                                  observation.getScopeText(),
                                  refs.getOrDefault(
                                      diaryRefKey(
                                          ReportDiaryEvidenceRef.OWNER_SESSION_OBSERVATION,
                                          observation.getDisplayOrder()),
                                      List.of())))
                      .toList(),
                  diaryCaregiverQuestionRepository
                      .findByReportIdOrderByDisplayOrderAsc(reportId)
                      .stream()
                      .map(
                          question ->
                              new DiaryCaregiverQuestionResponse(
                                  question.getQuestion(),
                                  question.getPurpose(),
                                  question.getConnectionType(),
                                  question.getResponseGuide(),
                                  question.getCoRegulationAction(),
                                  refs.getOrDefault(
                                      diaryRefKey(
                                          ReportDiaryEvidenceRef.OWNER_CAREGIVER_QUESTION,
                                          question.getDisplayOrder()),
                                      List.of())))
                      .toList(),
                  insight.getListeningTip(),
                  buildDiaryDevelopmentalObservations(reportId, refs),
                  diaryUnknownItemRepository.findByReportIdOrderByDisplayOrderAsc(reportId).stream()
                      .map(item -> new DiaryUnknownItemResponse(item.getCode(), item.getText()))
                      .toList(),
                  new DiaryDataQualityResponse(
                      insight.getConfirmedVoiceCount(),
                      insight.getOptionAnswerCount(),
                      insight.getSkippedCount(),
                      insight.getSttConfirmationCount(),
                      insight.getEvidenceCount(),
                      insight.isVisionSummaryAvailable()));
            })
        .orElse(null);
  }

  /**
   * 연령 발달 맥락 관찰을 만든다.
   *
   * <p>검수 출처가 비는 것은 정상이라 거르지 않는다 — AI 는 규준 문장(출처 있음)과 '이번 활동에서만 살펴본다'는 문장(규준을 주장하지 않아 출처 없음)을 함께
   * 보낸다. 출처는 도메인으로 한 번에 읽어 묶는다(관찰마다 조회하면 N+1 이 된다).
   */
  private List<DiaryDevelopmentalObservationResponse> buildDiaryDevelopmentalObservations(
      Long reportId, Map<String, List<DiaryEvidenceRefResponse>> refs) {
    // ⚠️ 출처는 조회하지 않는다 (S15P11B209-1010 v2). 보호자 응답에 출처 식별자를 싣지
    //    않기로 했고, 안 실을 값을 굳이 읽으면 언젠가 누가 다시 응답에 붙인다. 출처 내력은
    //    report_diary_development_sources 에 그대로 남아 있고 감사에서 읽는다.
    return diaryDevelopmentalObservationRepository
        .findByReportIdOrderByDisplayOrderAsc(reportId)
        .stream()
        .map(
            observation ->
                new DiaryDevelopmentalObservationResponse(
                    observation.getDomain(),
                    observation.getStatus(),
                    observation.getAgeContext(),
                    observation.getObservation(),
                    observation.getScopeText(),
                    observation.getContextType(),
                    observation.getCaregiverQuestion(),
                    refs.getOrDefault(
                        diaryRefKey(
                            ReportDiaryEvidenceRef.OWNER_DEVELOPMENTAL_OBSERVATION,
                            observation.getDisplayOrder()),
                        List.of())))
        .toList();
  }

  /** 다른 설명을 한 번에 읽어 카드 순서로 묶는다 — 카드마다 조회하면 N+1 이 된다. */
  private Map<Integer, List<String>> loadDiaryAlternatives(Long reportId) {
    Map<Integer, List<String>> grouped = new LinkedHashMap<>();
    diaryAlternativeRepository
        .findByReportIdOrderByObservationOrderAscDisplayOrderAsc(reportId)
        .forEach(
            alternative ->
                grouped
                    .computeIfAbsent(alternative.getObservationOrder(), key -> new ArrayList<>())
                    .add(alternative.getText()));
    return grouped;
  }

  /** 근거 참조를 한 번에 읽어 소유 항목별로 묶는다 — 항목마다 조회하면 N+1 이 된다. */
  private Map<String, List<DiaryEvidenceRefResponse>> loadDiaryEvidenceRefs(Long reportId) {
    Map<String, List<DiaryEvidenceRefResponse>> grouped = new LinkedHashMap<>();
    for (ReportDiaryEvidenceRef ref :
        diaryEvidenceRefRepository.findByReportIdOrderByOwnerTypeAscOwnerOrderAscDisplayOrderAsc(
            reportId)) {
      grouped
          .computeIfAbsent(
              diaryRefKey(ref.getOwnerType(), ref.getOwnerOrder()), key -> new ArrayList<>())
          .add(new DiaryEvidenceRefResponse(ref.getRefKind(), ref.getRefId()));
    }
    return grouped;
  }

  /** 소유 항목 종류와 순서를 묶음 키로 만든다. */
  private static String diaryRefKey(String ownerType, int ownerOrder) {
    return ownerType + "#" + ownerOrder;
  }
}
