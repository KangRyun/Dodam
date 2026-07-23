package com.ssafy.b209.conversation.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * 아동의 선택형 답변 제출 요청 DTO다.
 *
 * <p>{@code selectedOptions} 배열 순서는 저장 시 {@code selection_order}로 그대로 보존한다. {@code directText}는 문장
 * 직접 입력 값으로 미사용 시 {@code null}이다.
 *
 * @param questionMessageId 답변을 연결할 같은 대화 세션의 QUESTION 메시지 ID
 * @param selectedOptions 비어 있지 않은 선택 항목 배열
 * @param directText 선택적 문장 직접 입력 값
 */
public record OptionAnswerRequest(
    @NotNull @Positive Long questionMessageId,
    @NotEmpty @Valid List<SelectedOptionCommand> selectedOptions,
    @Size(max = 500) String directText) {}
