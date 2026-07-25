package com.ssafy.b209.auth.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 모바일 앱이 OAuth Provider에서 받은 Token을 서비스 로그인으로 교환하는 요청이다.
 *
 * <p>Provider별 허용 필드 조합은 Path의 Provider와 함께 Service 계층에서 검증한다.
 *
 * @param accessToken Kakao·Naver SDK가 발급한 Access Token
 * @param idToken Google SDK가 발급한 ID Token
 * @param deviceId 앱 설치 단위 식별자. 308번 Refresh Token 세션 저장에서 사용한다.
 */
@Schema(description = "모바일 OAuth Provider Token 로그인 요청")
public record OAuthLoginRequest(
    @Schema(description = "Kakao·Naver SDK가 발급한 Access Token", example = "provider-token")
        @Size(max = 4096)
        String accessToken,
    @Schema(description = "Google SDK가 발급한 ID Token") @Size(max = 4096) String idToken,
    @Schema(description = "Refresh Token 세션을 구분하는 앱 설치 단위 식별자", example = "mvp-device-001")
        @NotBlank
        @Size(max = 255)
        String deviceId) {}
