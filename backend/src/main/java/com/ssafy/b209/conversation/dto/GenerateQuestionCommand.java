package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.List;

/** 대화 서비스가 목표 계약 요청을 만들기 위한 입력값이다. */
public record GenerateQuestionCommand(
    Long conversationId,
    Long drawingSessionId,
    Long basisAnalysisId,
    int childAge,
    List<ResponseMode> allowedResponseModes,
    List<DetectedObject> detectedObjects,
    List<RecentMessage> recentMessages,
    String safetyRuleVersion) {}
