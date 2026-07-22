package com.ssafy.b209.analysis.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.time.Instant;
import java.util.List;

/**
 * 저장까지 완료된 그림 분석 실행과 객체 탐지 결과를 반환하는 공개 API 응답이다.
 *
 * @param drawingAnalysisId 생성된 분석 실행 식별자
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param drawingAssetId 분석한 그림 파일 식별자
 * @param requestId 서버가 생성한 Client 요청 UUID
 * @param analysisType 수행한 AI 분석 작업 유형
 * @param status 외부 계약의 분석 완료 상태
 * @param model 분석에 사용된 Model 정보
 * @param detections 탐지된 객체 목록이며 빈 목록을 허용함
 * @param requestedAt 서버가 분석 요청을 시작한 UTC 시각
 * @param processedAt Client가 분석을 끝낸 UTC 시각
 */
public record CreateDrawingAnalysisResponse(
    Long drawingAnalysisId,
    Long drawingSessionId,
    Long drawingAssetId,
    String requestId,
    DrawingAnalysisType analysisType,
    DrawingAnalysisStatus status,
    DrawingAnalysisModelResponse model,
    List<DrawingDetectionResponse> detections,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant requestedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant processedAt) {

  /**
   * 호출자가 가진 목록의 변경으로 공개 응답이 달라지지 않도록 Detection 목록을 복사한다.
   *
   * @param drawingAnalysisId 생성된 분석 실행 식별자
   * @param drawingSessionId 그림 활동 세션 식별자
   * @param drawingAssetId 분석한 그림 파일 식별자
   * @param requestId 서버가 생성한 Client 요청 UUID
   * @param analysisType 수행한 AI 분석 작업 유형
   * @param status 외부 계약의 분석 완료 상태
   * @param model 분석에 사용된 Model 정보
   * @param detections 탐지된 객체 목록
   * @param requestedAt 서버가 분석 요청을 시작한 UTC 시각
   * @param processedAt Client가 분석을 끝낸 UTC 시각
   */
  public CreateDrawingAnalysisResponse {
    detections = List.copyOf(detections);
  }
}
