package com.ssafy.b209.auth.service;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * OAuth Provider Token 검증에 사용하는 서버 측 애플리케이션 설정을 보관한다.
 *
 * @param kakao Kakao Token 소유 애플리케이션 검증 설정
 * @param google Google ID Token Audience 검증 설정
 * @param apple Apple Identity Token Audience 검증 설정
 * @param connectTimeout Provider 연결 제한 시간
 * @param readTimeout Provider 응답 제한 시간
 */
@ConfigurationProperties("app.auth.oauth")
public record OAuthProviderProperties(
    Kakao kakao, Google google, Apple apple, Duration connectTimeout, Duration readTimeout) {

  /** 누락된 제한 시간에 안전한 기본값을 적용한다. */
  public OAuthProviderProperties {
    connectTimeout = connectTimeout == null ? Duration.ofSeconds(3) : connectTimeout;
    readTimeout = readTimeout == null ? Duration.ofSeconds(5) : readTimeout;
  }

  /**
   * Kakao Token 정보 응답의 발급 애플리케이션을 검증하는 설정이다.
   *
   * @param appId Kakao Developers에 등록된 애플리케이션 ID
   */
  public record Kakao(String appId) {}

  /**
   * Google ID Token의 수신 대상을 검증하는 설정이다.
   *
   * @param clientId Flutter {@code serverClientId}와 동일한 Google Web Client ID
   */
  public record Google(String clientId) {}

  /**
   * Apple Identity Token의 수신 대상을 검증하는 설정이다.
   *
   * @param clientId Sign in with Apple이 활성화된 앱의 Bundle ID
   */
  public record Apple(String clientId) {}
}
