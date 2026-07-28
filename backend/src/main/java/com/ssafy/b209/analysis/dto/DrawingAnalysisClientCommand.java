package com.ssafy.b209.analysis.dto;

import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;

/**
 * Application Service가 그림 분석 Client에 전달하는 저장소 독립 명령이다.
 *
 * <p>HTTP Adapter는 {@code storageKey}를 직접 외부에 노출하지 않고 읽기 전용 URL로 변환한다.
 *
 * @param requestId HTTP Header로 전달할 호출 추적 식별자
 * @param analysisId Spring Boot가 먼저 저장한 분석 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param drawingAssetId 분석 대상 그림 파일 식별자
 * @param analysisScope 중간 또는 최종 분석 범위
 * @param activityType 저장된 그림 유형에서 확정한 AI 활동 유형
 * @param drawingSubject 저장된 HTP 단계 주제이며 그림일기는 {@code null}
 * @param storageKey 이미지 저장소의 안전한 상대 Key
 * @param mimeType 검증된 이미지 MIME Type
 * @param width 원본 이미지 너비
 * @param height 원본 이미지 높이
 * @param checksumSha256 원본 이미지 SHA-256 Checksum
 */
public record DrawingAnalysisClientCommand(
    @NotBlank String requestId,
    @NotNull @Positive Long analysisId,
    @NotNull @Positive Long drawingSessionId,
    @NotNull @Positive Long drawingAssetId,
    @NotNull DrawingAnalysisScope analysisScope,
    @NotNull DrawingAnalysisActivityType activityType,
    DrawingAnalysisSubject drawingSubject,
    @NotBlank @Pattern(regexp = "^(?![A-Za-z]:)(?!/)(?!.*(?:^|/)\\.{1,2}(?:/|$))(?!.*//).+(?<!/)$")
        String storageKey,
    @NotBlank @Pattern(regexp = "image/(png|jpeg)") String mimeType,
    @Positive Integer width,
    @Positive Integer height,
    @Pattern(regexp = "(?:sha256-)?[0-9a-fA-F]{64}") String checksumSha256) {

  /**
   * 활동 유형과 HTP 주제 조합이 내부 계약과 일치하는지 확인한다.
   *
   * @return HTP에는 주제가 있고 그림일기에는 주제가 없으면 {@code true}
   */
  @AssertTrue(message = "activityType and drawingSubject must match")
  public boolean isActivityContextValid() {
    return activityType == DrawingAnalysisActivityType.HTP
        ? drawingSubject != null
        : drawingSubject == null;
  }
}
