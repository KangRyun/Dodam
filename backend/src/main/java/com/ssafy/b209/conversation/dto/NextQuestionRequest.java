package com.ssafy.b209.conversation.dto;

import io.swagger.v3.oas.annotations.media.ArraySchema;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Positive;
import java.util.List;

/**
 * 다음 AI 질문 생성에 필요한 외부 요청 DTO다.
 *
 * <p>{@code previousAnswerMessageId}는 같은 대화 세션의 답변 메시지일 때만 후속 질문의 부모로 저장되며, 첫 질문은 생략해 {@code null}을
 * 사용한다.
 */
public record NextQuestionRequest(
    @Schema(description = "질문 근거가 되는 그림 분석 식별자", example = "1") @Positive Long basisAnalysisId,
    @Schema(description = "직전 답변 메시지 식별자(첫 질문은 생략)") @Positive Long previousAnswerMessageId,
    @ArraySchema(schema = @Schema(implementation = PreferredResponseMode.class, example = "EMOJI"))
        @NotEmpty
        List<PreferredResponseMode> preferredResponseModes) {}
