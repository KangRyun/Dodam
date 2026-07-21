package com.ssafy.b209.global.response;

import com.fasterxml.jackson.annotation.JsonPropertyOrder;

/**
 * Validation에 실패한 필드와 클라이언트에 전달할 안전한 메시지를 표현한다.
 *
 * <p>사용자가 입력한 원문인 {@code rejectedValue}와 내부 DTO 정보는 포함하지 않는다.
 *
 * @param field Validation에 실패한 필드명
 * @param message 클라이언트에 전달할 안전한 Validation 메시지
 */
@JsonPropertyOrder({"field", "message"})
public record FieldErrorDetail(String field, String message) {}
