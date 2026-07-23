package com.ssafy.b209.conversation.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 아동이 실제로 선택한 하나의 선택지 항목이다. 요청 검증과 응답 재생에 함께 사용한다.
 *
 * <p>네 값은 모두 질문 메시지 선택지 Snapshot({@code conversation_message_options})과 일치해야 저장을 허용한다.
 *
 * @param optionId 질문 선택지의 {@code option_key}와 일치해야 하는 선택지 식별자
 * @param type 질문 선택지 Snapshot의 {@code option_type}과 일치해야 하는 선택지 유형
 * @param value 질문 선택지 Snapshot의 {@code option_value}와 일치해야 하는 선택지 값
 * @param labelSnapshot 화면에 노출된 문구로 서버 선택지의 {@code label}과 일치해야 하는 값
 */
public record SelectedOptionCommand(
    @NotBlank @Size(max = 80) String optionId,
    @NotBlank @Size(max = 30) String type,
    @NotBlank @Size(max = 255) String value,
    @NotBlank @Size(max = 200) String labelSnapshot) {}
