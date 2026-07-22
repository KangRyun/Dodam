package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthProvider;
import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Kakao·Google·Naver authorization code 교환에 사용하는 서버 측 Client 설정을 보관한다.
 *
 * @param kakao Kakao REST API Client 설정
 * @param google Google OAuth Client 설정
 * @param naver Naver Login Client 설정
 * @param connectTimeout Provider 연결 제한 시간
 * @param readTimeout Provider 응답 제한 시간
 */
@ConfigurationProperties("app.auth.oauth")
public record OAuthProviderProperties(
    Provider kakao,
    Provider google,
    Provider naver,
    Duration connectTimeout,
    Duration readTimeout) {

  /** 누락된 제한 시간에 안전한 기본값을 적용한다. */
  public OAuthProviderProperties {
    connectTimeout = connectTimeout == null ? Duration.ofSeconds(3) : connectTimeout;
    readTimeout = readTimeout == null ? Duration.ofSeconds(5) : readTimeout;
  }

  /**
   * 요청한 Provider의 Client 설정을 반환한다.
   *
   * @param provider OAuth Provider
   * @return Provider별 설정 또는 설정되지 않았으면 {@code null}
   */
  public Provider forProvider(AuthProvider provider) {
    return switch (provider) {
      case KAKAO -> kakao;
      case GOOGLE -> google;
      case NAVER -> naver;
    };
  }

  /**
   * OAuth Provider Console에 등록한 서버 Client 정보이다.
   *
   * @param clientId 공개 Client ID 또는 Kakao REST API Key
   * @param clientSecret 서버에서만 보관하는 Client Secret
   * @param redirectUri Provider Console에 등록한 Redirect URI
   */
  public record Provider(String clientId, String clientSecret, String redirectUri) {}
}
