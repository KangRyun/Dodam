package com.ssafy.b209.drawing.dto.response;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.ssafy.b209.drawing.domain.DrawingInputMethod;
import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import java.time.Instant;

/**
 * 그림 활동 세션 생성 결과와 서버가 생성한 공식 시작 시각을 반환하는 응답이다.
 *
 * @param drawingSessionId 생성된 그림 활동 세션 식별자
 * @param childId 그림 활동을 시작한 아동 식별자
 * @param drawingType 선택된 그림 활동 유형 요약
 * @param inputMethod 그림 입력 방식
 * @param sessionStatus 현재 세션 처리 상태
 * @param currentStage 현재 진행 단계
 * @param tutorialRequired 아동의 튜토리얼 필요 여부
 * @param startedAt 서버가 생성한 공식 시작 시각
 */
public record CreateDrawingSessionResponse(
    Long drawingSessionId,
    Long childId,
    DrawingTypeSummaryResponse drawingType,
    DrawingInputMethod inputMethod,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage,
    boolean tutorialRequired,
    @JsonFormat(shape = JsonFormat.Shape.STRING) Instant startedAt) {}
