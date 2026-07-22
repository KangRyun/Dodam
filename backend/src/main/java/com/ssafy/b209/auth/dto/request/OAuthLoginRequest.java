package com.ssafy.b209.auth.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 앱이 OAuth Provider에서 받은 일회성 authorization code를 서비스 로그인으로 교환하는 요청이다.
 *
 * @param authorizationCode OAuth Provider가 발급한 일회성 code
 * @param redirectUri code 발급 요청에 사용했고 서버 설정과 정확히 일치하는 URI
 * @param state Naver code 발급 요청과 응답에 사용한 state, 다른 Provider에서는 {@code null} 가능
 * @param deviceId 앱 설치 단위 식별자. 308번 Refresh Token 세션 저장에서 사용한다.
 */
public record OAuthLoginRequest(
    @NotBlank @Size(max = 2048) String authorizationCode,
    @NotBlank @Size(max = 1000) String redirectUri,
    @Size(max = 255) String state,
    @NotBlank @Size(max = 255) String deviceId) {}
