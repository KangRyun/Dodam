package com.ssafy.b209.drawing.dto.request;

import jakarta.validation.constraints.NotNull;

/**
 * 그림 활동의 최종 분석과 선택적 리포트 생성을 접수하는 요청이다.
 *
 * @param conversationSkipped 대화를 시작하지 않고 생략했으면 {@code true}
 * @param requestReport 보호자 리포트 생성도 함께 요청하면 {@code true}
 */
public record CompleteDrawingSessionRequest(
    @NotNull Boolean conversationSkipped, @NotNull Boolean requestReport) {}
