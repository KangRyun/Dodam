package com.ssafy.b209.conversation.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Positive;

/** 최종 API 명세의 대화 세션 시작 요청 DTO다. */
public record StartConversationRequest(
    @Schema(description = "대화 근거가 되는 그림 분석 식별자", example = "1") @Positive Long analysisId,
    @Schema(description = "최대 질문 수(1~10)", example = "5") @Positive @Max(10)
        Integer maxQuestionCount) {}
