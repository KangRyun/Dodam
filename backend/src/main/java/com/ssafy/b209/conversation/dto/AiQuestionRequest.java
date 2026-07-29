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
     * <p>⚠️ 선택 필드다. 분석이 없거나 서술 생성이 실패했으면 {@code null}이고, 이때 AI는 기존 객체 기반 질문으로 그대로 동작한다.
     */
    String drawingDescription,
    List<RecentMessage> recentMessages,
    String safetyRuleVersion,
    /**
     * 서버가 확정한 그림 활동 유형이다(S15P11B209-712).
     *
     * <p>{@code "HTP"} 또는 {@code "ART_DIARY"}이며, HTP 주제 확정에 실패하면 {@code null}이다. FE 입력이 아니라 저장된 세션
     * 관계에서 서버가 결정한다.
     */
    String activityType,
    /**
     * 서버가 확정한 HTP 그림 주제다(S15P11B209-712).
     *
     * <p>{@code "HOUSE"}, {@code "TREE"}, {@code "PERSON"} 중 하나이며, 그림일기이거나 주제 확정에 실패하면 {@code
     * null}이다.
     */
    String drawingSubject,
    /**
     * 이 대화에서 이미 질문한 대상 객체 Code 목록이다(S15P11B209-712).
     *
     * <p>대화 전체 메시지에서 중복 없이 모은 값이며, 대상이 없으면 빈 리스트다.
     */
    List<String> askedObjectCodes) {}
