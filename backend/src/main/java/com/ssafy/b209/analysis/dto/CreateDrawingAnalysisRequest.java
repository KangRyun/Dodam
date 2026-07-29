package com.ssafy.b209.analysis.dto;

import com.ssafy.b209.analysis.domain.DrawingAnalysisTriggerReason;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * 저장된 그림 파일에 새 분석 실행을 요청하는 공개 API 입력이다.
 *
 * @param drawingAssetId 분석 대상 그림 파일 Metadata 식별자
 * @param analysisType 수행할 AI 분석 작업 유형
 * @param triggerReason 분석 실행을 요청한 직접적인 계기
 */
public record CreateDrawingAnalysisRequest(
    @Schema(description = "분석 대상 그림 파일 Metadata 식별자(최종 스냅샷의 drawingAssetId)", example = "1")
        @NotNull
        @Positive
        Long drawingAssetId,
    @Schema(description = "수행할 AI 분석 작업 유형", example = "OBJECT_DETECTION") @NotNull
        DrawingAnalysisType analysisType,
    @Schema(
            description = "분석 실행 사유. 생략하면 기존 Client 호환을 위해 USER_REQUEST로 처리한다.",
            example = "PAUSE",
            defaultValue = "USER_REQUEST")
        DrawingAnalysisTriggerReason triggerReason) {

  /** 기존 Client와 내부 호출이 실행 사유를 생략하면 명시적인 사용자 요청으로 해석한다. */
  public CreateDrawingAnalysisRequest {
    if (triggerReason == null) {
      triggerReason = DrawingAnalysisTriggerReason.USER_REQUEST;
    }
  }

  /**
   * 실행 사유 필드가 추가되기 전의 내부 호출을 호환한다.
   *
   * @param drawingAssetId 분석 대상 그림 파일 식별자
   * @param analysisType 수행할 분석 유형
   */
  public CreateDrawingAnalysisRequest(Long drawingAssetId, DrawingAnalysisType analysisType) {
    this(drawingAssetId, analysisType, DrawingAnalysisTriggerReason.USER_REQUEST);
  }

  /**
   * 공개 분석 API가 현재 지원하는 자동 중단 및 명시적 요청 사유인지 확인한다.
   *
   * @return {@code PAUSE} 또는 {@code USER_REQUEST}이면 {@code true}
   */
  @AssertTrue(message = "triggerReason must be PAUSE or USER_REQUEST")
  public boolean isSupportedPublicTriggerReason() {
    return triggerReason == DrawingAnalysisTriggerReason.PAUSE
        || triggerReason == DrawingAnalysisTriggerReason.USER_REQUEST;
  }
}
