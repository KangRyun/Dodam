package com.ssafy.b209.auth.token;

/**
 * 로그인 성공 시 발급한 Access Token과 Refresh Token 묶음이다.
 *
 * @param accessToken API 인증에 사용할 단기 JWT
 * @param accessTokenExpiresInSeconds Access Token 만료까지 남은 초
 * @param refreshToken 재발급에만 사용할 장기 JWT
 * @param refreshTokenExpiresInSeconds Refresh Token 만료까지 남은 초
 */
public record IssuedTokenPair(
    String accessToken,
    long accessTokenExpiresInSeconds,
    String refreshToken,
    long refreshTokenExpiresInSeconds) {}
