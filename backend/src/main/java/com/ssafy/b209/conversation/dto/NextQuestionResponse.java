package com.ssafy.b209.conversation.dto;

import java.time.Instant;
import java.util.List;

/** 외부 앱에 반환하는 저장 완료 AI 질문 메시지다. */
public record NextQuestionResponse(
    Long messageId,
    Long conversationId,
    int sequence,
    String senderType,
    String messageType,
    String text,
    List<NextQuestionOptionResponse> options,
    NextQuestionTargetResponse targetObject,
    boolean ttsAvailable,
    Instant createdAt) {}
