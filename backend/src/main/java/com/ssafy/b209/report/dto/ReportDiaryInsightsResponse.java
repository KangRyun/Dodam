package com.ssafy.b209.report.dto;

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
 * @param dataQuality 근거가 무엇으로 이루어졌는지 알려 주는 구성 정보
 */
public record ReportDiaryInsightsResponse(
    DiaryStorySnapshotResponse storySnapshot,
    List<DiaryNarrativeStepResponse> narrativeFlow,
    List<DiaryChildVoiceResponse> childVoiceItems,
    List<DiarySessionObservationResponse> sessionObservations,
    List<DiaryCaregiverQuestionResponse> caregiverQuestions,
    String listeningTip,
    DiaryDataQualityResponse dataQuality) {

  /** 목록은 빈 목록으로 정규화한다. 앱이 null 검사를 섹션마다 하지 않아도 되게 한다. */
  public ReportDiaryInsightsResponse {
    narrativeFlow = narrativeFlow == null ? List.of() : List.copyOf(narrativeFlow);
    childVoiceItems = childVoiceItems == null ? List.of() : List.copyOf(childVoiceItems);
    sessionObservations =
        sessionObservations == null ? List.of() : List.copyOf(sessionObservations);
    caregiverQuestions = caregiverQuestions == null ? List.of() : List.copyOf(caregiverQuestions);
  }

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
   * @param title 보호자에게 보이는 제목
   * @param description 근거에 묶인 이번 활동 한정 설명
   * @param scopeText 범위를 알리는 문구이며 카드에 함께 보여 준다
   * @param evidenceRefs 서로 다른 근거 식별자
   */
  public record DiarySessionObservationResponse(
      String observationCode,
      String title,
      String description,
      String scopeText,
      List<DiaryEvidenceRefResponse> evidenceRefs) {

    /** 근거 목록은 빈 목록으로 정규화한다. */
    public DiarySessionObservationResponse {
      evidenceRefs = evidenceRefs == null ? List.of() : List.copyOf(evidenceRefs);
    }
  }

  /**
   * 보호자가 아이에게 그대로 물어볼 수 있는 질문이다.
   *
   * @param question 질문 한 문장
   * @param purpose 이 질문으로 더 들어볼 내용이며 없으면 {@code null}
   * @param evidenceRefs 이 질문이 이어지는 근거 식별자
   */
  public record DiaryCaregiverQuestionResponse(
      String question, String purpose, List<DiaryEvidenceRefResponse> evidenceRefs) {

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
}
