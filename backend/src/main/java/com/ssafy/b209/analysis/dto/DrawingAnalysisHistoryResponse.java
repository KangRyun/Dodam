package com.ssafy.b209.analysis.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.analysis.domain.DrawingAnalysisScope;
import com.ssafy.b209.analysis.domain.DrawingAnalysisState;
import java.time.Instant;

/**
 * 활동별 그림 분석 이력 목록의 한 항목이다.
 *
 * <p>목록 조회에 필요한 상태 요약만 포함하며 객체 탐지 결과는 분석 상세 조회에서 제공한다. 내부 저장 위치는 포함하지 않는다.
 *
 * @param drawingAnalysisId 분석 실행 식별자
 * @param drawingAssetId 분석 대상 그림 파일 식별자
 * @param scope 중간 또는 최종 분석 범위
 * @param taskType AI 분석 작업 유형
 * @param state 분석 처리 상태
 * @param requestedAt 분석 요청 시각
 * @param completedAt 분석 종료 시각, 진행 중이면 {@code null}
 */
public record DrawingAnalysisHistoryResponse(
    Long drawingAnalysisId,
    Long drawingAssetId,
    DrawingAnalysisScope scope,
    DrawingAnalysisType taskType,
    DrawingAnalysisState state,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant requestedAt,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant completedAt) {}
