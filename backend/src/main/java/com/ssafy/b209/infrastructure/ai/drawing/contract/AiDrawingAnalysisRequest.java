package com.ssafy.b209.infrastructure.ai.drawing.contract;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;
import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import java.util.List;

/**
 * AI 서버의 종합 그림 분석 Endpoint에 전달하는 §19.3 요청 계약이다.
 *
 * <p>아동의 이름과 생년월일은 포함하지 않으며, 선택 입력을 사용할 수 없으면 필수 그림 정보만 전달한다.
 *
 * @param analysisId Spring Boot가 먼저 생성한 분석 식별자
 * @param drawingSessionId 분석 대상 그림 활동 세션 식별자
 * @param activityType 분석 모델을 선택하는 활동 유형
 * @param drawingSubject HTP 단계 주제이며 그림일기는 {@code null}
 * @param analysisType 중간 또는 최종 분석 범위
 * @param triggerReason 분석 실행 사유
 * @param childContext 개인정보를 제외한 아동 분석 맥락
 * @param drawing 분석할 그림의 읽기 전용 접근 정보
 * @param behavior 그림 과정 데이터
 * @param conversation 대화 메시지
 * @param reflection 활동 종료 시 아동이 직접 선택하거나 표현한 감정
 * @param rag 근거 검색 조건
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record AiDrawingAnalysisRequest(
    @NotNull @Positive Long analysisId,
    @NotNull @Positive Long drawingSessionId,
    @NotNull DrawingAnalysisActivityType activityType,
    DrawingAnalysisSubject drawingSubject,
    @NotNull AnalysisType analysisType,
    TriggerReason triggerReason,
    @Valid ChildContext childContext,
    @NotNull @Valid DrawingInput drawing,
    @Valid BehaviorInput behavior,
    @Valid ConversationInput conversation,
    @Valid ReflectionInput reflection,
    @Valid RagInput rag) {

  /**
   * 현재 저장된 그림 정보만 사용하는 최소 정본 요청을 생성한다.
   *
   * @param analysisId 분석 식별자
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param activityType 분석 모델을 선택하는 활동 유형
   * @param drawingSubject HTP 단계 주제이며 그림일기는 {@code null}
   * @param analysisType 분석 범위
   * @param drawing 그림 접근 정보
   * @return 선택 입력을 포함하지 않는 분석 요청
   */
  public static AiDrawingAnalysisRequest minimum(
      Long analysisId,
      Long drawingSessionId,
      DrawingAnalysisActivityType activityType,
      DrawingAnalysisSubject drawingSubject,
      AnalysisType analysisType,
      DrawingInput drawing) {
    return new AiDrawingAnalysisRequest(
        analysisId,
        drawingSessionId,
        activityType,
        drawingSubject,
        analysisType,
        null,
        null,
        drawing,
        null,
        null,
        null,
        null);
  }

  /**
   * 활동 유형과 HTP 주제 조합이 AI 계약과 일치하는지 확인한다.
   *
   * @return HTP에는 주제가 있고 그림일기에는 주제가 없으면 {@code true}
   */
  @AssertTrue(message = "activityType and drawingSubject must match")
  public boolean isActivityContextValid() {
    return activityType == DrawingAnalysisActivityType.HTP
        ? drawingSubject != null
        : drawingSubject == null;
  }

  /** AI가 수행할 분석 범위다. */
  public enum AnalysisType {
    /** 자동 저장된 중간 그림을 분석한다. */
    INTERMEDIATE,
    /** 활동 완료 그림과 사용 가능한 부가 입력을 종합 분석한다. */
    FINAL
  }

  /** 분석을 시작한 원인을 나타낸다. */
  public enum TriggerReason {
    /** 일시 정지를 계기로 실행한다. */
    PAUSE,
    /** 일정 시간 간격으로 실행한다. */
    INTERVAL,
    /** 획 수 기준으로 실행한다. */
    STROKE_COUNT,
    /** 그림 변화율 기준으로 실행한다. */
    CHANGE_RATIO,
    /** 사용자가 직접 요청했다. */
    USER_REQUEST,
    /** 그림 저장 완료를 계기로 실행한다. */
    DRAWING_COMPLETE,
    /** 활동 전체 완료를 계기로 실행한다. */
    ACTIVITY_COMPLETE,
    /** 실패 분석을 재시도한다. */
    RETRY
  }

  /**
   * 분석에 필요한 최소 아동 맥락이다.
   *
   * @param age 만 나이
   * @param ageGroup 연령 그룹
   * @param questionDifficulty 질문 난이도
   */
  public record ChildContext(
      @Positive int age, @NotBlank String ageGroup, @NotBlank String questionDifficulty) {}

  /**
   * AI 서버가 그림을 읽고 무결성을 확인하는 데 필요한 정보다.
   *
   * @param drawingAssetId 그림 파일 Metadata 식별자
   * @param signedUrl 짧은 만료 시간을 가진 읽기 전용 URL
   * @param mimeType 검증된 이미지 MIME Type
   * @param width 원본 이미지 너비
   * @param height 원본 이미지 높이
   * @param checksumSha256 원본 이미지 SHA-256 Checksum
   */
  public record DrawingInput(
      @NotNull @Positive Long drawingAssetId,
      @NotBlank @Pattern(regexp = "https?://.+") String signedUrl,
      @NotBlank @Pattern(regexp = "image/(png|jpeg)") String mimeType,
      @Positive Integer width,
      @Positive Integer height,
      @Pattern(regexp = "(?:sha256-)?[0-9a-fA-F]{64}") String checksumSha256) {}

  /**
   * 그림 과정 데이터와 서버 집계값이다.
   *
   * @param strokeBatchUrls 획 Batch를 읽을 수 있는 URL 목록
   * @param summary 그림 과정 집계값
   */
  public record BehaviorInput(
      @NotNull List<@NotBlank String> strokeBatchUrls, @Valid BehaviorSummary summary) {

    /** 전달받은 목록을 이후 변경할 수 없도록 복사한다. */
    public BehaviorInput {
      strokeBatchUrls = strokeBatchUrls == null ? null : List.copyOf(strokeBatchUrls);
    }
  }

  /**
   * 그림 과정에서 계산된 통계다.
   *
   * @param drawingDurationMs 전체 그림 시간
   * @param activeDrawingMs 실제 입력 시간
   * @param pauseCount 일시 정지 횟수
   * @param undoCount 실행 취소 횟수
   * @param eraseCount 지우기 횟수
   * @param toolChangeCount 도구 변경 횟수
   * @param colorChangeCount 색상 변경 횟수
   * @param pressureAvailable 필압 데이터 사용 가능 여부
   */
  public record BehaviorSummary(
      Long drawingDurationMs,
      Long activeDrawingMs,
      Integer pauseCount,
      Integer undoCount,
      Integer eraseCount,
      Integer toolChangeCount,
      Integer colorChangeCount,
      boolean pressureAvailable) {}

  /**
   * 분석 시점까지 저장된 대화다.
   *
   * @param messages 시간순 대화 메시지
   */
  public record ConversationInput(@NotNull List<@NotNull @Valid ConversationMessage> messages) {

    /** 전달받은 목록을 이후 변경할 수 없도록 복사한다. */
    public ConversationInput {
      messages = messages == null ? null : List.copyOf(messages);
    }
  }

  /**
   * 분석 입력으로 사용하는 대화 한 건이다.
   *
   * @param messageId 저장된 메시지 식별자
   * @param senderType 발신자 유형
   * @param messageType 메시지 유형
   * @param text 저장된 텍스트이며 음성 원본은 포함하지 않음
   */
  public record ConversationMessage(
      Long messageId, @NotBlank String senderType, @NotBlank String messageType, String text) {}

  /**
   * 활동 종료 시 아동이 직접 표현한 감정 입력이다.
   *
   * @param selectedEmotions 선택한 감정 코드
   * @param expressedEmotionText 자유 표현
   */
  public record ReflectionInput(
      @NotNull List<@NotBlank String> selectedEmotions, String expressedEmotionText) {

    /** 전달받은 목록을 이후 변경할 수 없도록 복사한다. */
    public ReflectionInput {
      selectedEmotions = selectedEmotions == null ? null : List.copyOf(selectedEmotions);
    }
  }

  /**
   * 근거 검색 범위를 제한하는 입력이다.
   *
   * @param knowledgeBaseVersion 지식 베이스 버전
   * @param allowedSourceTypes 허용할 출처 유형
   * @param maxReferences 최대 근거 수
   */
  public record RagInput(
      String knowledgeBaseVersion,
      @NotNull List<@NotBlank String> allowedSourceTypes,
      @Positive int maxReferences) {

    /** 전달받은 목록을 이후 변경할 수 없도록 복사한다. */
    public RagInput {
      allowedSourceTypes = allowedSourceTypes == null ? null : List.copyOf(allowedSourceTypes);
    }
  }
}
