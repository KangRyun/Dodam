package com.ssafy.b209.conversation.dto;

import java.util.List;

/**
 * 대화 내역 조회에서 선택형 답변 메시지의 저장된 선택 응답을 재생한다.
 *
 * @param selectedOptions 선택 순서대로 재생한 선택 항목 목록
 * @param directText 저장한 문장 직접 입력 값 또는 {@code null}
 */
public record ConversationMessageSelectedResponse(
    List<SelectedOptionCommand> selectedOptions, String directText) {}
