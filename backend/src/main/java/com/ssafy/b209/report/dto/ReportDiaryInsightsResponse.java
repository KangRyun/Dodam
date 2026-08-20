package com.ssafy.b209.report.dto;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 그림일기 리포트 V2 응답이다.
 *
 * <p>리포트 상세 응답의 {@code diaryInsights} 자리에 실리며, <strong>없으면 {@code null}</strong>이다. 앱은 이 값의 유무로 화면을
 * 가른다 — 있으면 V2 화면, 없으면 기존 리포트 화면이다. HTP 리포트이거나, 그림일기지만 근거가 부족해 구조화할 것이 없었으면 {@code null}이 온다.
 *
 * <p>빈 배열은 정상이다. 그 섹션을 화면에서 숨기라는 뜻이며, 채우기 위해 일반론을 만들지 않는다는 이 리포트의 원칙이 그대로 드러난 결과다.
 *
 * @param storySnapshot 이번 이야기의 핵심이며 없으면 {@code null}
 * @param narrativeFlow 사건 → 아이 행동 → 상대 반응 → 감정 → 바람 → 결과 중 확인된 단계만 시간 순서대로
 * @param childVoiceItems 아이가 실제로 한 말과 그 말을 끌어낸 질문 방식
 * @param sessionObservations 이번 활동에서만 확인된 표현이며 0~2개다
 * @param caregiverQuestions 보호자가 그대로 이어 물을 질문이며 0~2개다
 * @param listeningTip 이번 이야기를 들을 때의 태도 한 문장이며 없으면 {@code null}
 * @param developmentalObservations 연령 발달 맥락과 이번 활동 관찰을 짝지은 항목이다. 앱은 <strong>맥락·관찰·범위 고지를 항상
 *     함께</strong> 보여 준다 — 맥락만 떼면 규준 설명이 되고, 범위 고지를 빼면 한 회차가 발달 평가로 읽힌다
 * @param unknownItems 이번 활동에서 확인하지 못한 것이다. 카드가 비어 나가면 보호자는 '문제가 없었다'로 읽는다 — 침묵 대신 무엇을 알 수 없었는지 이름을
 *     붙여 돌려준다
 * @param dataQuality 근거가 무엇으로 이루어졌는지 알려 주는 구성 정보
 * @param schemaVersion 그림일기 구조 버전
 * @param dataScope V3 자료 범위와 집계이며 V2는 {@code null}
 * @param storyComponents V3 이야기 지도 구성 요소
 * @param drawingObservations V3 이미지 기반 관찰 사실
 * @param transcript 리포트 생성 시점의 전체 질문·답변 스냅샷
 */
public record ReportDiaryInsightsResponse(
    DiaryStorySnapshotResponse storySnapshot,
    List<DiaryNarrativeStepResponse> narrativeFlow,
    List<DiaryChildVoiceResponse> childVoiceItems,
    List<DiarySessionObservationResponse> sessionObservations,
    List<DiaryCaregiverQuestionResponse> caregiverQuestions,
    String listeningTip,
    List<DiaryDevelopmentalObservationResponse> developmentalObservations,
    List<DiaryUnknownItemResponse> unknownItems,
    DiaryDataQualityResponse dataQuality,
    int schemaVersion,
    DiaryDataScopeResponse dataScope,
    List<DiaryStoryComponentResponse> storyComponents,
    List<DiaryDrawingObservationResponse> drawingObservations,
    List<DiaryTranscriptEntryResponse> transcript) {

  /** 목록은 빈 목록으로 정규화한다. 앱이 null 검사를 섹션마다 하지 않아도 되게 한다. */
  public ReportDiaryInsightsResponse {
    narrativeFlow = narrativeFlow == null ? List.of() : List.copyOf(narrativeFlow);
    childVoiceItems = childVoiceItems == null ? List.of() : List.copyOf(childVoiceItems);
    sessionObservations =
        sessionObservations == null ? List.of() : List.copyOf(sessionObservations);
    caregiverQuestions = caregiverQuestions == null ? List.of() : List.copyOf(caregiverQuestions);
    developmentalObservations =
        developmentalObservations == null ? List.of() : List.copyOf(developmentalObservations);
    unknownItems = unknownItems == null ? List.of() : List.copyOf(unknownItems);
    storyComponents = storyComponents == null ? List.of() : List.copyOf(storyComponents);
    drawingObservations =
        drawingObservations == null ? List.of() : List.copyOf(drawingObservations);
    transcript = transcript == null ? List.of() : List.copyOf(transcript);
  }

  /** V3 필드가 없던 조회 조립부와 테스트를 위한 V2 호환 생성자다. */
  public ReportDiaryInsightsResponse(
      DiaryStorySnapshotResponse storySnapshot,
      List<DiaryNarrativeStepResponse> narrativeFlow,
      List<DiaryChildVoiceResponse> childVoiceItems,
      List<DiarySessionObservationResponse> sessionObservations,
      List<DiaryCaregiverQuestionResponse> caregiverQuestions,
      String listeningTip,
      List<DiaryDevelopmentalObservationResponse> developmentalObservations,
      List<DiaryUnknownItemResponse> unknownItems,
      DiaryDataQualityResponse dataQuality) {
    this(
        storySnapshot,
        narrativeFlow,
        childVoiceItems,
        sessionObservations,
        caregiverQuestions,
        listeningTip,
        developmentalObservations,
        unknownItems,
        dataQuality,
        2,
        null,
        List.of(),
        List.of(),
        List.of());
  }

  /**
   * 이번 리포트가 실제로 사용한 자료 범위다.
   *
   * @param evidenceLevel LIMITED·PARTIAL·RICH 중 하나
   * @param summary 보호자에게 보여 줄 자료 범위 설명
   * @param confirmedVoiceCount 확정된 아이 발화 수
   * @param optionAnswerCount 선택형 답변 수
   * @param skippedCount 건너뛴 질문 수
   * @param sttConfirmationCount 확인이 필요한 STT 수
   * @param visualObservationCount 검증된 그림 관찰 수
   */
  public record DiaryDataScopeResponse(
      String evidenceLevel,
      String summary,
      int confirmedVoiceCount,
      int optionAnswerCount,
      int skippedCount,
      int sttConfirmationCount,
      int visualObservationCount) {}

  /**
   * 이야기 지도 구성 요소 하나다.
   *
   * @param componentType 구성 요소 종류
   * @param confirmationStatus 근거 확인 상태
   * @param text 확인된 내용이며 UNKNOWN이면 {@code null}
   * @param evidenceRefs 구성 요소의 근거 참조
   */
  public record DiaryStoryComponentResponse(
      String componentType,
      String confirmationStatus,
      String text,
      List<DiaryEvidenceRefResponse> evidenceRefs) {

    public DiaryStoryComponentResponse {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 이미지에서 직접 확인한 사실 하나다.
   *
   * @param text 그림 관찰 문장
   * @param confidence HIGH·MODERATE·LOW 중 하나
   * @param childConfirmed 아이 발화로도 확인됐는지 여부
   * @param evidenceRefs 관찰의 이미지 근거 참조
   */
  public record DiaryDrawingObservationResponse(
      String text,
      String confidence,
      boolean childConfirmed,
      List<DiaryEvidenceRefResponse> evidenceRefs) {

    public DiaryDrawingObservationResponse {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 리포트 생성 시점의 질문·답변 한 쌍과 현재 음성 재생 계약이다.
   *
   * @param questionMessageId 질문 메시지 식별자
   * @param answerMessageId 답변 메시지 식별자
   * @param questionText 질문 원문
   * @param answerText 답변 원문 또는 확정 STT이며 없으면 {@code null}
   * @param responseType VOICE·OPTION·TEXT·SKIPPED·CORRECTION 중 하나
   * @param sttStatus 음성 처리 상태이며 음성이 아니면 {@code null}
   * @param audioDurationMs 실제 수집한 음성 길이이며 알 수 없으면 {@code null}
   * @param audioAvailable 현재 원본 음성 참조가 있어 재생을 시도할 수 있는지 여부
   * @param audioUrl JWT 인증이 필요한 상대 Proxy 경로이며 재생할 수 없으면 {@code null}
   * @param elicitationType 답변을 이끈 질문 방식
   * @param createdAt 답변 메시지 생성 시각이며 과거 데이터는 {@code null}
   */
  public record DiaryTranscriptEntryResponse(
      Long questionMessageId,
      Long answerMessageId,
      String questionText,
      String answerText,
      String responseType,
      String sttStatus,
      Integer audioDurationMs,
      boolean audioAvailable,
      String audioUrl,
      String elicitationType,
      LocalDateTime createdAt) {}

  /**
   * 이번 그림일기의 핵심 이야기다.
   *
   * @param headline 이야기의 핵심을 짧게 적은 제목
   * @param summary 사건·아이 행동·상대 반응을 이은 요약
   * @param realityStatus {@code REAL}·{@code IMAGINED}·{@code MIXED}·{@code UNKNOWN}. 아이가 말한 경우에만
   *     {@code UNKNOWN} 밖의 값이 온다 — 앱은 상상 이야기를 있었던 일처럼 보여 주지 않는다
   * @param timeScope {@code TODAY}·{@code YESTERDAY}·{@code RECENT}·{@code PAST}·{@code UNKNOWN}.
   *     아이가 시점을 말하지 않았으면 {@code UNKNOWN} 이며, 활동한 날짜로 대신 채우면 안 된다
   * @param mainEvent 중심 사건이며 분명하지 않으면 {@code null}
   * @param evidenceRefs 이 요약을 뒷받침하는 근거 식별자
   */
  public record DiaryStorySnapshotResponse(
      String headline,
      String summary,
      String realityStatus,
      String timeScope,
      String mainEvent,
      List<DiaryEvidenceRefResponse> evidenceRefs) {

    /** 근거 목록은 빈 목록으로 정규화한다. */
    public DiaryStorySnapshotResponse {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 이야기 흐름의 한 단계다.
   *
   * @param stepType {@code EVENT}·{@code CHILD_ACTION}·{@code OTHER_RESPONSE}·{@code
   *     EMOTION}·{@code WISH}·{@code OUTCOME} 중 하나이며, 앱이 사용자 문구로 바꿔 보여 준다
   * @param text 그 단계에서 확인된 내용
   * @param evidenceRefs 이 단계를 뒷받침하는 근거 식별자
   */
  public record DiaryNarrativeStepResponse(
      String stepType, String text, List<DiaryEvidenceRefResponse> evidenceRefs) {

    /** 근거 목록은 빈 목록으로 정규화한다. */
    public DiaryNarrativeStepResponse {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 아이가 실제로 한 말 한 건이다.
   *
   * @param text 아이가 한 말 그대로
   * @param elicitationType 그 말을 끌어낸 질문 방식이다. 선택지에서 고른 답을 자발 표현처럼 보여 주지 않기 위한 구분이라 앱도 이 값을 함께 보여 준다
   * @param answerType 답변 입력 방식이며 없으면 {@code null}
   * @param sourceRef 이 발화의 근거 식별자이며 없으면 {@code null}
   * @param sttNeedsConfirmation 음성 인식 확인이 필요한 답이면 {@code true}
   */
  public record DiaryChildVoiceResponse(
      String text,
      String elicitationType,
      String answerType,
      DiaryEvidenceRefResponse sourceRef,
      boolean sttNeedsConfirmation) {}

  /**
   * 이번 활동에서 확인된 표현이다. 지속적인 심리 경향이 아니다.
   *
   * @param observationCode 관찰 코드
   * @param insightType 주장의 세기다. {@code CONFIRMED_EXPRESSION}(아이가 한 말)·{@code SESSION_HYPOTHESIS}(다른
   *     설명과 함께여야 성립)·{@code EXPLORE_NEXT}(뜻을 정하지 않은 단서). 앱은 이 값으로 카드의 말투와 표시를 가른다
   * @param domain 인사이트 영역
   * @param title 보호자에게 보이는 제목
   * @param description 근거에 묶인 이번 활동 한정 설명
   * @param hypothesis 이번 회차 한정 가설이며 없으면 {@code null}
   * @param alternativeExplanations 다르게 볼 수 있는 설명이다. <strong>가설과 반드시 함께 보여 준다</strong> — 하나의 해석만 보이면
   *     보호자는 그것을 결론으로 읽는다
   * @param clarificationQuestion 다음에 확인할 질문이며 없으면 {@code null}
   * @param scopeText 범위를 알리는 문구이며 카드에 함께 보여 준다
   * @param evidenceRefs 근거 식별자
   */
  public record DiarySessionObservationResponse(
      String observationCode,
      String insightType,
      String domain,
      String title,
      String description,
      String hypothesis,
      List<String> alternativeExplanations,
      String clarificationQuestion,
      String scopeText,
      List<DiaryEvidenceRefResponse> evidenceRefs) {

    /** 목록은 빈 목록으로 정규화한다. */
    public DiarySessionObservationResponse {
      alternativeExplanations =
          alternativeExplanations == null ? List.of() : List.copyOf(alternativeExplanations);
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * "오늘 마음 나누기" 교감 카드다. 앱은 💬 {@code question} / 🤍 {@code responseGuide} / (있으면)🎨 {@code
   * coRegulationAction} 을 한 카드로 함께 보여 준다.
   *
   * <p>{@code responseGuide}·{@code coRegulationAction} 은 서버가 {@code connectionType} 으로 정적 매핑한 값이며
   * LLM 이 만들지 않는다.
   *
   * @param question 감정 앵커 질문 한 문장
   * @param purpose 이 질문으로 더 들어볼 내용이며 없으면 {@code null}
   * @param connectionType 교감 유형({@code FEELING_SHARING}·{@code COMFORT_SEEKING}·{@code
   *     SHARED_JOY}·{@code PERSPECTIVE_TAKING}·{@code GENERAL_CONNECTION})
   * @param responseGuide 아이 답에 부모가 마음으로 반응하는 법이며 없으면 {@code null}
   * @param coRegulationAction 함께 해보기 한 줄이며 없으면 {@code null}
   * @param evidenceRefs 이 질문이 이어지는 근거 식별자
   */
  public record DiaryCaregiverQuestionResponse(
      String question,
      String purpose,
      String connectionType,
      String responseGuide,
      String coRegulationAction,
      List<DiaryEvidenceRefResponse> evidenceRefs) {

    /** 근거 목록은 빈 목록으로 정규화한다. */
    public DiaryCaregiverQuestionResponse {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 이번 리포트의 근거가 무엇으로 이루어졌는지 알려 준다.
   *
   * @param confirmedVoiceCount 음성으로 확정된 답변 수
   * @param optionAnswerCount 선택지에서 고른 답변 수
   * @param skippedCount 건너뛴 질문 수
   * @param sttConfirmationCount 음성 인식 확인이 필요한 답변 수
   * @param evidenceCount 사용된 근거 수
   * @param visionSummaryAvailable 그림 관찰 서술이 있었으면 {@code true}
   */
  public record DiaryDataQualityResponse(
      int confirmedVoiceCount,
      int optionAnswerCount,
      int skippedCount,
      int sttConfirmationCount,
      int evidenceCount,
      boolean visionSummaryAvailable) {}

  /**
   * 구조화 항목이 가리키는 근거 식별자다.
   *
   * @param kind 근거 종류(예: {@code QA_ANSWER})
   * @param id BE 가 발급한 식별자 그대로
   */
  public record DiaryEvidenceRefResponse(String kind, String id) {}

  /**
   * 연령 발달 맥락 관찰 한 건이다.
   *
   * <p>앱은 <strong>연령 맥락 → 이번 활동 관찰 → 범위 고지</strong> 세 조각을 항상 함께 보여 준다. 맥락만 보여 주면 규준 설명이 되고, 범위 고지를
   * 빼면 한 회차가 발달 평가로 읽힌다.
   *
   * @param domain {@code NARRATIVE_LANGUAGE}·{@code EMOTION_EXPRESSION}·{@code
   *     SOCIAL_UNDERSTANDING}·{@code COPING_HELP_SEEKING}·{@code SELF_REFLECTION}
   * @param status {@code OBSERVED_THIS_SESSION}·{@code PARTIALLY_OBSERVED}·{@code NOT_ASSESSED}.
   *     <strong>{@code NOT_ASSESSED} 를 '지연'으로 보여 주면 안 된다</strong> — 이번에 확인하지 않았다는 뜻이다
   * @param ageContext 검수된 공개 자료에서 온 연령 맥락 한 줄
   * @param observation 이번 활동에서 확인된 표현
   * @param scopeText 범위 고지이며 화면에 항상 함께 나간다
   * @param contextType {@code AGE_MILESTONE_CONTEXT}·{@code
   *     EARLY_SCHOOL_COMMUNICATION_CONTEXT}·{@code SESSION_ONLY_CONTEXT}. 화면이 "연령 이정표"와 "학령 초기 참고
   *     맥락"과 "이번 활동만"을 섞지 않게 한다
   * @param caregiverQuestion 보호자가 활동에 이어 그대로 물어볼 수 있는 질문이며 없으면 {@code null}
   * @param evidenceRefs 이번 활동 관찰의 근거 식별자
   */
  public record DiaryDevelopmentalObservationResponse(
      String domain,
      String status,
      String ageContext,
      String observation,
      String scopeText,
      String contextType,
      String caregiverQuestion,
      List<DiaryEvidenceRefResponse> evidenceRefs) {

    /**
     * 목록은 빈 목록으로 정규화한다.
     *
     * <p>⚠️ {@code sourceIds} 를 보호자 응답에서 뺐다 (S15P11B209-1010 v2). 문서명·기관명·URL 은 물론 출처
     * <strong>식별자</strong>도 화면에 나가지 않는다 — 식별자가 나가면 앱이 그것으로 출처를 그릴 수 있고, 그러면 "숨긴다"가 클라이언트 구현에 기댄 약속이
     * 된다. 출처 내력은 내부 엔티티 ({@code report_diary_development_sources})와 AI 등록부에 그대로 남는다.
     */
    public DiaryDevelopmentalObservationResponse {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 이번 활동에서 확인하지 못한 것 한 건이다.
   *
   * @param code 서버가 정한 코드
   * @param text 보호자에게 보이는 문구
   */
  public record DiaryUnknownItemResponse(String code, String text) {}
}
