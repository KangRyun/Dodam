package com.ssafy.b209.analysis.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.validation.Valid;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.List;

/**
 * AI 서버가 Spring Boot에 반환하는 그림 분석 응답 계약이다.
 *
 * <p>상태별 허용 Payload를 명확히 구분한다. 성공 응답의 {@code detections}는 비어 있을 수 있으며 실패 응답은 안전한 오류 정보만 포함한다.
 *
 * @param requestId 요청과 응답을 연결하는 요청 식별자
 * @param status AI 분석 진행 상태
 * @param model 성공 시 분석에 사용된 모델 정보
 * @param detections 탐지된 객체 목록
 * @param error 실패 시 안전하게 정제된 오류 정보
 * @param processedAt 성공 또는 실패 처리가 끝난 UTC 시각
 */
public record DrawingAnalysisResponse(
    @NotBlank String requestId,
    @NotNull DrawingAnalysisStatus status,
    @Valid DrawingAnalysisModelResponse model,
    @NotNull List<@NotNull @Valid DrawingDetectionResponse> detections,
    @Valid DrawingAnalysisErrorResponse error,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant processedAt) {

  /**
   * 호출자가 전달한 탐지 목록의 이후 변경이 응답 계약에 영향을 주지 않도록 방어적으로 복사한다.
   *
   * @param requestId 요청과 응답을 연결하는 요청 식별자
   * @param status AI 분석 진행 상태
   * @param model 성공 시 분석에 사용된 모델 정보
   * @param detections 탐지된 객체 목록
   * @param error 실패 시 안전하게 정제된 오류 정보
   * @param processedAt 성공 또는 실패 처리가 끝난 UTC 시각
   */
  public DrawingAnalysisResponse {
    detections = detections == null ? null : List.copyOf(detections);
  }

  /**
   * 상태와 선택적 Payload 조합이 계약에 맞는지 검증한다.
   *
   * <p>검증용 파생 값은 JSON 응답 필드로 노출하지 않는다.
   *
   * @return 성공·실패·진행 상태에 맞는 Payload 조합이면 {@code true}
   */
  @JsonIgnore
  @AssertTrue(message = "status에 맞지 않는 그림 분석 응답입니다.")
  public boolean isPayloadConsistent() {
    if (status == null || detections == null) {
      return false;
    }
    return switch (status) {
      case SUCCEEDED -> model != null && error == null && processedAt != null;
      case FAILED -> model == null && detections.isEmpty() && error != null && processedAt != null;
      case PENDING, PROCESSING ->
          model == null && detections.isEmpty() && error == null && processedAt == null;
    };
  }
}
