package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.ConversationDifficulty;
import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.List;

/** Spring Boot에서 FastAPI로 보내는 목표 내부 질문 생성 요청 DTO다. */
public record AiQuestionRequest(
    Long conversationId,
    Long drawingSessionId,
    Long basisAnalysisId,
    int childAge,
    ConversationDifficulty difficulty,
    List<ResponseMode> allowedResponseModes,
    int currentQuestionCount,
    int maxQuestionCount,
    List<DetectedObject> detectedObjects,
    List<RecentMessage> recentMessages,
    String safetyRuleVersion) {}
