package com.ssafy.b209.conversation.dto;

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
    @Positive Long basisAnalysisId,
    @Positive Long previousAnswerMessageId,
    @NotEmpty List<PreferredResponseMode> preferredResponseModes) {}
