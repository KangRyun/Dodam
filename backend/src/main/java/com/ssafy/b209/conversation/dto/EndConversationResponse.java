package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.conversation.domain.ConversationCompletionReason;
import com.ssafy.b209.drawing.domain.DrawingStage;
import java.time.LocalDateTime;

/**
 * 대화 종료 처리 후 저장된 대화 상태와 다음 그림 활동 단계를 반환하는 응답 계약이다.
 *
 * @param conversationId 종료된 대화 세션 식별자
 * @param conversationStatus 저장된 대화 상태 문자열
 * @param completed 대화 종료 여부
 * @param completionReason 최초로 저장된 대화 종료 사유
 * @param completedAt 최초로 저장된 대화 종료 시각
 * @param nextStage 대화 종료 후 진행할 그림 활동 단계
 */
public record EndConversationResponse(
    Long conversationId,
    String conversationStatus,
    boolean completed,
    ConversationCompletionReason completionReason,
    LocalDateTime completedAt,
    DrawingStage nextStage) {}
