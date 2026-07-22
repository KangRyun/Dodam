package com.ssafy.b209.auth.service;

/**
 * OAuth 로그인 성공 후 앱에 전달할 Token과 사용자 상태이다.
 *
 * @param grantType HTTP Authorization Header에 사용할 Bearer Scheme
 * @param accessToken 단기 API 인증 JWT
 * @param accessTokenExpiresInSeconds Access Token 만료까지 남은 초
 * @param refreshToken 토큰 재발급에만 사용할 JWT
 * @param refreshTokenExpiresInSeconds Refresh Token 만료까지 남은 초
 * @param user 로그인한 사용자 상태
 */
public record OAuthLoginResult(
    String grantType,
    String accessToken,
    long accessTokenExpiresInSeconds,
    String refreshToken,
    long refreshTokenExpiresInSeconds,
    OAuthLoginUser user) {}
