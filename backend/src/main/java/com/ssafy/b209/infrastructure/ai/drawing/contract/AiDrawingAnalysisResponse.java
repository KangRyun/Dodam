package com.ssafy.b209.infrastructure.ai.drawing.contract;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.PositiveOrZero;
import java.math.BigDecimal;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * AI 서버가 반환하는 §19.4 종합 그림 분석 응답 계약이다.
 *
 * <p>일부 입력을 사용하지 못한 경우에도 사용한 결과와 누락 사유를 함께 전달할 수 있다. 관찰 초안은 전문가 검토 전 보호자에게 직접 노출해서는 안 된다.
 *
 * @param analysisId Spring Boot가 요청에서 전달한 분석 식별자
 * @param status 종합 분석 처리 상태
 * @param modelInfo 분석 구성요소별 Model 정보
 * @param detectedObjects 정규화 좌표를 포함한 객체 탐지 결과
 * @param visualFeatures 이미지에서 계산한 시각 특징
 * @param behaviorFeatures 그림 과정 데이터에서 계산한 행동 특징
 * @param conversationSummary 대화 요약과 집계
 * @param observationDraft 전문가 검토 전 관찰 초안
 * @param evidenceReferences 관찰 문장을 뒷받침하는 근거
 * @param unusedInputs 사용하지 못한 입력과 사유
 * @param warnings 비치명적 처리 경고 코드
 * @param processingTimeMs AI 서버 처리 시간
 */
public record AiDrawingAnalysisResponse(
    @NotNull @Positive Long analysisId,
    @NotNull AnalysisStatus status,
    @NotNull @Valid ModelInfo modelInfo,
    @NotNull List<@NotNull @Valid DetectedObject> detectedObjects,
    @NotNull Map<String, Object> visualFeatures,
    @NotNull Map<String, Object> behaviorFeatures,
    @Valid ConversationSummary conversationSummary,
    @Valid ObservationDraft observationDraft,
    @NotNull List<@NotNull @Valid EvidenceReference> evidenceReferences,
    @NotNull List<@NotNull @Valid UnusedInput> unusedInputs,
    @NotNull List<@NotBlank String> warnings,
    @PositiveOrZero long processingTimeMs) {

  /** Collection 결과를 호출 이후 변경할 수 없도록 방어적으로 복사한다. */
  public AiDrawingAnalysisResponse {
    detectedObjects = detectedObjects == null ? null : List.copyOf(detectedObjects);
    visualFeatures = immutableNullableMap(visualFeatures);
    behaviorFeatures = immutableNullableMap(behaviorFeatures);
    evidenceReferences = evidenceReferences == null ? null : List.copyOf(evidenceReferences);
    unusedInputs = unusedInputs == null ? null : List.copyOf(unusedInputs);
    warnings = warnings == null ? null : List.copyOf(warnings);
  }

  private static Map<String, Object> immutableNullableMap(Map<String, Object> source) {
    return source == null ? null : Collections.unmodifiableMap(new LinkedHashMap<>(source));
  }

  /**
   * 부분 성공 응답이 실제 누락 사유를 포함하는지 검증한다.
   *
   * @return 상태와 누락 사유 조합이 유효하면 {@code true}
   */
  @JsonIgnore
  @AssertTrue(message = "PARTIAL_SUCCESS 응답에는 unusedInputs가 필요합니다.")
  public boolean isPartialSuccessConsistent() {
    return status != AnalysisStatus.PARTIAL_SUCCESS
        || (unusedInputs != null && !unusedInputs.isEmpty());
  }

  /** AI 서버가 반환할 수 있는 종합 분석 완료 상태다. */
  public enum AnalysisStatus {
    /** 모든 사용 가능한 입력을 처리했다. */
    SUCCESS,
    /** 일부 입력을 사용하지 못했지만 유효한 결과를 만들었다. */
    PARTIAL_SUCCESS,
    /** 종합 분석 결과를 만들지 못했다. */
    FAILED
  }

  /**
   * 분석 구성요소별 Model 식별 정보다.
   *
   * @param objectDetection 객체 탐지 Model
   * @param vision 이미지 설명 Model
   * @param language 언어 Model
   * @param knowledgeBaseVersion 근거 검색 지식 베이스 버전
   */
  public record ModelInfo(
      @Valid ModelRef objectDetection,
      @Valid ModelRef vision,
      @Valid ModelRef language,
      String knowledgeBaseVersion) {}

  /**
   * 단일 Model 이름과 버전이다.
   *
   * @param name Model 이름
   * @param version Model 버전
   */
  public record ModelRef(@NotBlank String name, @NotBlank String version) {}

  /**
   * 그림에서 탐지된 객체다.
   *
   * @param objectCode 계약에서 사용하는 객체 코드
   * @param objectName 사용자 표시용 한국어 객체명
   * @param confidence 0~1 탐지 신뢰도
   * @param boundingBox 0~1 정규화 영역
   * @param areaRatio 전체 그림에서 객체 영역이 차지하는 비율
   * @param detectionOrder 탐지 결과 순서
   */
  public record DetectedObject(
      @NotBlank String objectCode,
      String objectName,
      @NotNull @DecimalMin("0.0") @DecimalMax("1.0") BigDecimal confidence,
      @NotNull @Valid BoundingBox boundingBox,
      @DecimalMin("0.0") @DecimalMax("1.0") BigDecimal areaRatio,
      @PositiveOrZero int detectionOrder) {}

  /**
   * 좌측 상단을 원점으로 사용하는 0~1 정규화 Bounding Box다.
   *
   * @param x 좌측 상단 X 좌표
   * @param y 좌측 상단 Y 좌표
   * @param width 영역 너비
   * @param height 영역 높이
   */
  public record BoundingBox(
      @NotNull @DecimalMin("0.0") @DecimalMax("1.0") BigDecimal x,
      @NotNull @DecimalMin("0.0") @DecimalMax("1.0") BigDecimal y,
      @NotNull @DecimalMin(value = "0.0", inclusive = false) @DecimalMax("1.0") BigDecimal width,
      @NotNull @DecimalMin(value = "0.0", inclusive = false) @DecimalMax("1.0") BigDecimal height) {

    /**
     * Bounding Box가 정규화 Canvas 경계를 벗어나지 않는지 확인한다.
     *
     * @return 우측과 하단 경계가 1 이하이면 {@code true}
     */
    @JsonIgnore
    @AssertTrue(message = "Bounding Box는 정규화 Canvas 경계를 벗어날 수 없습니다.")
    public boolean isWithinCanvas() {
      return x == null
          || y == null
          || width == null
          || height == null
          || (x.add(width).compareTo(BigDecimal.ONE) <= 0
              && y.add(height).compareTo(BigDecimal.ONE) <= 0);
    }
  }

  /**
   * 분석 시점까지의 대화 요약과 집계다.
   *
   * @param summaryText AI가 생성한 대화 요약
   * @param representativeUtterance 저장된 실제 대표 발화
   * @param questionCount 질문 수
   * @param responseCount 응답 수
   * @param skippedQuestionCount 건너뛴 질문 수
   * @param unrecognizedSpeechCount 음성 인식 실패 수
   */
  public record ConversationSummary(
      String summaryText,
      String representativeUtterance,
      @PositiveOrZero int questionCount,
      @PositiveOrZero int responseCount,
      @PositiveOrZero int skippedQuestionCount,
      @PositiveOrZero int unrecognizedSpeechCount) {}

  /**
   * 전문가 검토 전 관찰 결과 초안이다.
   *
   * @param status 검토 상태
   * @param overallSummary 전체 관찰 요약
   * @param observations 관찰 문장
   * @param followUpQuestions 후속 질문
   * @param expertReviewRequired 전문가 검토 필요 여부
   * @param disclaimer 진단이 아니라는 필수 주의 문구
   */
  public record ObservationDraft(
      @NotBlank String status,
      String overallSummary,
      @NotNull List<@NotBlank String> observations,
      @NotNull List<@NotBlank String> followUpQuestions,
      boolean expertReviewRequired,
      @NotBlank String disclaimer) {

    /** 전달받은 문장 목록을 이후 변경할 수 없도록 복사한다. */
    public ObservationDraft {
      observations = observations == null ? null : List.copyOf(observations);
      followUpQuestions = followUpQuestions == null ? null : List.copyOf(followUpQuestions);
    }
  }

  /**
   * RAG 기반 관찰 문장을 뒷받침하는 근거다.
   *
   * @param sourceId 지식 베이스 출처 식별자
   * @param title 출처 제목
   * @param authors 저자 목록
   * @param publishedYear 발행 연도
   * @param section 참조 구역
   * @param evidenceType 근거 유형
   * @param applicability 적용 범위
   * @param limitations 적용 한계
   * @param knowledgeBaseVersion 지식 베이스 버전
   * @param retrievedChunkHash 검색 Chunk Hash
   */
  public record EvidenceReference(
      @NotBlank String sourceId,
      @NotBlank String title,
      @NotNull List<@NotBlank String> authors,
      Integer publishedYear,
      String section,
      @NotBlank String evidenceType,
      String applicability,
      String limitations,
      String knowledgeBaseVersion,
      String retrievedChunkHash) {

    /** 전달받은 저자 목록을 이후 변경할 수 없도록 복사한다. */
    public EvidenceReference {
      authors = authors == null ? null : List.copyOf(authors);
    }
  }

  /**
   * 분석에서 사용하지 못한 입력과 사유다.
   *
   * @param sourceType 입력 출처 유형
   * @param reasonCode 제외 사유 코드
   * @param reasonDetail 안전하게 정제된 상세 사유
   * @param retryable 조건이 달라지면 재시도할 수 있는지 여부
   */
  public record UnusedInput(
      @NotBlank String sourceType,
      @NotBlank String reasonCode,
      String reasonDetail,
      boolean retryable) {}
}
