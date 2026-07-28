package com.ssafy.b209.analysis.service;

import com.ssafy.b209.analysis.dto.DrawingAnalysisActivityType;
import com.ssafy.b209.analysis.dto.DrawingAnalysisSubject;

/**
 * 저장된 그림 세션과 HTP 단계를 바탕으로 확정한 AI 모델 선택 맥락이다.
 *
 * @param activityType AI와 합의된 활동 유형
 * @param drawingSubject HTP 단계 주제이며 그림일기는 {@code null}
 */
public record DrawingAnalysisActivityContext(
    DrawingAnalysisActivityType activityType, DrawingAnalysisSubject drawingSubject) {}
