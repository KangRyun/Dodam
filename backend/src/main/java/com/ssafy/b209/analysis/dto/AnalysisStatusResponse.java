package com.ssafy.b209.analysis.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

/**
 * 분석 식별자만으로 폴링하는 공개 API의 상태와 보호자 공개 가능 결과를 반환한다.
 *
 * <p>{@code analysisType}은 중간·최종 분석 시점을, {@code analysisTaskType}은 수행한 AI 작업을 구분한다. 실패 상세는 내부 저장
 * 메시지를 노출하지 않고 안전한 공통 오류로 변환한다.
 *
 * @param analysisId 분석 실행 식별자
 * @param drawingSessionId 분석이 속한 그림 활동 세션 식별자
 * @param drawingAssetId 분석 대상 그림 파일 식별자
 * @param analysisType 중간 또는 최종 분석 시점
 * @param analysisTaskType 수행한 AI 작업 유형
 * @param analysisStatus 저장된 분석 처리 상태
 * @param confidence 분석 전체 신뢰도이며 제공되지 않았으면 {@code null}
 * @param modelName 완료된 분석의 Model 이름
 * @param modelVersion 완료된 분석의 Model 버전
 * @param requestedAt 분석 요청 UTC 시각
 * @param completedAt 성공 또는 실패 처리 UTC 시각
 * @param detectedObjects 보호자에게 공개 가능한 객체 탐지 결과
 * @param failureCode 실패 시 안전하게 변환한 오류 코드
 * @param message 실패 시 사용자에게 표시할 수 있는 오류 메시지
 */
public record AnalysisStatusResponse(
    Long analysisId,
    Long drawingSessionId,
    Long drawingAssetId,
    DrawingAnalysisScope analysisType,
    DrawingAnalysisType analysisTaskType,
    DrawingAnalysisState analysisStatus,
    BigDecimal confidence,
    String modelName,
    String modelVersion,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant requestedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant completedAt,
    List<AnalysisDetectedObjectResponse> detectedObjects,
    String failureCode,
    String message) {

  /** 응답 생성 후 외부 목록 변경의 영향을 받지 않도록 객체 탐지 목록을 복사한다. */
  public AnalysisStatusResponse {
    detectedObjects = List.copyOf(detectedObjects);
  }
}
