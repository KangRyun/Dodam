package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;

/**
 * 최종 그림 저장과 대화 준비용 분석이 확정된 그림 단계 완료 결과다.
 *
 * @param drawingSessionId 그림 활동 세션 식별자
 * @param finalAssetId 저장하거나 재사용한 FINAL 그림 파일 식별자
 * @param sessionStatus 그림 활동 세션 처리 상태
 * @param currentStage 그림 활동의 현재 단계
 * @param analysis 대화 준비용 객체 탐지 분석 상태
 * @param nextAction 클라이언트가 이어서 수행할 동작
 */
public record CompleteDrawingStageResponse(
    Long drawingSessionId,
    Long finalAssetId,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage,
    DrawingStageAnalysisResponse analysis,
    String nextAction) {}
