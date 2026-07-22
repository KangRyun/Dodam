package com.ssafy.b209.auth.token;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 서비스 JWT 서명과 만료 정책을 보관한다.
 *
 * @param secret HS256 서명에 사용할 32 Byte 이상의 서버 Secret
 * @param issuer 서비스 Token 발급자
 * @param accessTokenTtl Access Token 유효 기간
 * @param refreshTokenTtl Refresh Token 유효 기간
 */
@ConfigurationProperties("app.auth.jwt")
public record JwtProperties(
    String secret, String issuer, Duration accessTokenTtl, Duration refreshTokenTtl) {}
