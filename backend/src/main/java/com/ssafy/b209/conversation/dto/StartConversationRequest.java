package com.ssafy.b209.conversation.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Positive;

/** 최종 API 명세의 대화 세션 시작 요청 DTO다. */
public record StartConversationRequest(
    @Schema(description = "대화 근거가 되는 그림 분석 식별자", example = "1") @Positive Long analysisId,
    @Schema(
            description =
                "최대 질문 수(선택). 보내지 않는 것이 기본이며, 서버가 활동 유형별 정책으로 정한다"
                    + "(S15P11B209-976). 보내더라도 정책값보다 낮출 때만 반영되고, 더 큰 값은 정책값으로 낮춰진다. "
                    + "응답의 maxQuestionCount 가 실제로 적용된 값이다.",
            example = "3")
        @Positive
        @Max(10)
        Integer maxQuestionCount) {}
