package com.ssafy.b209.conversation.dto;

import com.ssafy.b209.child.domain.QuestionDifficulty;
import com.ssafy.b209.conversation.domain.ResponseMode;
import java.util.List;

/** Spring Boot에서 FastAPI로 보내는 목표 내부 질문 생성 요청 DTO다. */
public record AiQuestionRequest(
    Long conversationId,
    Long drawingSessionId,
    Long basisAnalysisId,
    int childAge,
    QuestionDifficulty difficulty,
    List<ResponseMode> allowedResponseModes,
    int currentQuestionCount,
    int maxQuestionCount,
    List<DetectedObject> detectedObjects,
    /**
     * 그림 서술(VLM) — 분석에서 만든 2~4문장 한국어 관찰 서술이다(S15P11B209-704).
     *
     * <p>출처는 {@code analysis_observation_results.overall_summary}이며 {@code basisAnalysisId}로 찾는다.
     * 객체 이름 목록만으로는 색·표정·구도를 근거로 한 질문이 나올 수 없어 함께 보낸다.
     *
     * <p>⚠️ 선택 필드다. 분석이 없거나 서술 생성이 실패했으면 {@code null}이고, 이때 AI는 기존 객체 기반
     * 질문으로 그대로 동작한다.
     */
    String drawingDescription,
    List<RecentMessage> recentMessages,
    String safetyRuleVersion) {}
