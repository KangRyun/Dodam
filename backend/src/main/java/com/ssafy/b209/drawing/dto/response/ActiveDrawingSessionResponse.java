package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import java.time.Instant;

/**
 * 아동이 재개할 수 있는 진행 중 그림 활동 세션과 최신 자동 저장 초안을 반환하는 응답이다.
 *
 * <p>조회 시 세션 상태를 변경하지 않으며, 저장된 초안이 없으면 {@code latestDraft}는 {@code null}이다.
 *
 * @param drawingSessionId 진행 중 그림 활동 세션 식별자
 * @param childId 그림 활동을 수행하는 아동 식별자
 * @param drawingType 선택된 그림 활동 유형 요약
 * @param inputMethod 그림 입력 방식
 * @param sessionStatus 현재 세션 처리 상태
 * @param currentStage 현재 진행 단계
 * @param startedAt 서버가 기록한 세션 시작 시각
 * @param latestDraft 가장 최근 자동 저장 초안, 저장된 초안이 없으면 {@code null}
 */
public record ActiveDrawingSessionResponse(
    Long drawingSessionId,
    Long childId,
    DrawingTypeSummaryResponse drawingType,
    DrawingInputMethod inputMethod,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant startedAt,
    LatestDrawingDraftResponse latestDraft) {}
