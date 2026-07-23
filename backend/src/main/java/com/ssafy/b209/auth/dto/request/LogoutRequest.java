package com.ssafy.b209.auth.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 현재 기기의 Refresh Token 세션을 폐기하는 로그아웃 요청이다.
 *
 * @param refreshToken 현재 기기에 마지막으로 발급된 Refresh JWT
 * @param deviceId Refresh Token을 발급받은 앱 설치 단위 식별자
 */
public record LogoutRequest(
    @NotBlank @Size(max = 4096) String refreshToken, @NotBlank @Size(max = 255) String deviceId) {}
