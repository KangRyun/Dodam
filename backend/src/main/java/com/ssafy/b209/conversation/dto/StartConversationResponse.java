package com.ssafy.b209.conversation.dto;

import java.time.Instant;

/** 대화 세션 생성 직후 다음 질문 요청을 안내하는 공개 응답 DTO다. */
public record StartConversationResponse(
    Long conversationId,
    Long drawingSessionId,
    String status,
    String difficulty,
    int maxQuestionCount,
    int questionCount,
    String nextAction,
    Instant startedAt) {}
