package com.ssafy.b209.auth.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 유효한 Refresh Token을 새 Access·Refresh Token 묶음으로 교환하는 요청이다.
 *
 * @param refreshToken 직전 로그인 또는 재발급에서 받은 Refresh JWT
 * @param deviceId Refresh Token을 최초 발급받은 앱 설치 단위 식별자
 */
public record TokenReissueRequest(
    @NotBlank @Size(max = 4096) String refreshToken, @NotBlank @Size(max = 255) String deviceId) {}
