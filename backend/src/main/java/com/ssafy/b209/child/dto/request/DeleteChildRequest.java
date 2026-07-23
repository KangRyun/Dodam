package com.ssafy.b209.child.dto.request;

import jakarta.validation.constraints.NotBlank;

/**
 * 아동 프로필 삭제의 명시적 확인 값을 전달한다.
 *
 * @param confirmation 오작동 방지를 위해 정확히 {@code DELETE}여야 하는 확인 문자열
 */
public record DeleteChildRequest(@NotBlank String confirmation) {}
