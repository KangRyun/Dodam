package com.ssafy.b209.conversation.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Positive;

/** 최종 API 명세의 대화 세션 시작 요청 DTO다. */
public record StartConversationRequest(
    @Positive Long analysisId, @Positive @Max(10) Integer maxQuestionCount) {}
