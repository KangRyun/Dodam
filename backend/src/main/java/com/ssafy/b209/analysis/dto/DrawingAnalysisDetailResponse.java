package com.ssafy.b209.analysis.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.time.Instant;
import java.util.List;

/**
 * 저장된 그림 분석의 진행 상태와 공개 가능한 객체 탐지 결과를 반환한다.
 *
 * @param drawingAnalysisId 분석 실행 식별자
 * @param drawingSessionId 분석이 속한 그림 활동 세션 식별자
 * @param drawingAssetId 분석 대상 그림 파일 식별자
 * @param requestId 분석 요청과 저장 결과를 연결하는 UUID
 * @param analysisType 수행한 AI 분석 작업 유형
 * @param status 외부 API에 공개하는 분석 상태
 * @param model 성공한 분석에 사용된 Model 정보
 * @param detections 저장 순서대로 정렬된 객체 탐지 결과
 * @param requestedAt 서버가 분석을 요청한 UTC 시각
 * @param processedAt 성공 또는 실패 처리가 끝난 UTC 시각
 * @param failure 실패한 분석의 안전한 공개 오류 정보
 */
public record DrawingAnalysisDetailResponse(
    Long drawingAnalysisId,
    Long drawingSessionId,
    Long drawingAssetId,
    String requestId,
    DrawingAnalysisType analysisType,
    DrawingAnalysisStatus status,
    DrawingAnalysisModelResponse model,
    List<DrawingDetectionResponse> detections,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant requestedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant processedAt,
    DrawingAnalysisFailureResponse failure) {

  /** 응답 생성 후 외부 목록 변경의 영향을 받지 않도록 Detection 목록을 복사한다. */
  public DrawingAnalysisDetailResponse {
    detections = List.copyOf(detections);
  }
}
