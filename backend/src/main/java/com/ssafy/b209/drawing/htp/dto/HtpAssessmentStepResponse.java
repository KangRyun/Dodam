package com.ssafy.b209.drawing.htp.dto;

import com.ssafy.b209.drawing.domain.DrawingSessionStatus;
import com.ssafy.b209.drawing.domain.DrawingStage;
import com.ssafy.b209.drawing.htp.domain.HtpDrawingSubject;

/**
 * HTP 화면이 임의 추정 없이 현재 그림 주제와 연결 세션으로 이동할 수 있도록 제공하는 단계 응답이다.
 *
 * @param stepOrder HOUSE부터 시작하는 1~3 순서
 * @param drawingSubject 서버가 지정한 현재 그림 주제
 * @param drawingSessionId 현재 단계의 기존 그림 세션 식별자
 * @param sessionStatus 그림 세션 처리 상태
 * @param currentStage 그림 세션 진행 단계
 */
public record HtpAssessmentStepResponse(
    int stepOrder,
    HtpDrawingSubject drawingSubject,
    Long drawingSessionId,
    DrawingSessionStatus sessionStatus,
    DrawingStage currentStage) {}
