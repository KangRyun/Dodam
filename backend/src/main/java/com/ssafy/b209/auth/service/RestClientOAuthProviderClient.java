package com.ssafy.b209.auth.service;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

/**
 * Kakao·Naver Access Token을 Provider REST API에서 검증하고 Google·Apple ID Token 검증을 전용 구현에 위임한다.
 *
 * <p>전달받은 Provider Token은 요청 중에만 사용하며 저장하거나 로그에 기록하지 않는다.
 */
@Component
public class RestClientOAuthProviderClient implements OAuthProviderClient {

  private static final String KAKAO_TOKEN_INFO_URI =
      "https://kapi.kakao.com/v1/user/access_token_info";
  private static final String KAKAO_USER_URI = "https://kapi.kakao.com/v2/user/me";
  private static final String NAVER_USER_URI = "https://openapi.naver.com/v1/nid/me";

  private final RestClient restClient;
  private final OAuthProviderProperties properties;
  private final GoogleIdTokenVerifier googleIdTokenVerifier;
  private final AppleIdTokenVerifier appleIdTokenVerifier;

  /**
   * Provider API Client를 구성한다.
   *
   * @param builder Spring이 제공하는 RestClient Builder
   * @param properties Provider 애플리케이션과 통신 제한 시간 설정
   * @param googleIdTokenVerifier Google ID Token 로컬 검증기
   * @param appleIdTokenVerifier Apple Identity Token 로컬 검증기
   */
  @Autowired
  public RestClientOAuthProviderClient(
      RestClient.Builder builder,
      OAuthProviderProperties properties,
      GoogleIdTokenVerifier googleIdTokenVerifier,
      AppleIdTokenVerifier appleIdTokenVerifier) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(properties.connectTimeout());
    requestFactory.setReadTimeout(properties.readTimeout());
    this.restClient = builder.requestFactory(requestFactory).build();
    this.properties = properties;
    this.googleIdTokenVerifier = googleIdTokenVerifier;
    this.appleIdTokenVerifier = appleIdTokenVerifier;
  }

  RestClientOAuthProviderClient(
      RestClient restClient,
      OAuthProviderProperties properties,
      GoogleIdTokenVerifier googleIdTokenVerifier,
      AppleIdTokenVerifier appleIdTokenVerifier) {
    this.restClient = restClient;
    this.properties = properties;
    this.googleIdTokenVerifier = googleIdTokenVerifier;
    this.appleIdTokenVerifier = appleIdTokenVerifier;
  }

  /**
   * Provider Token을 검증해 불변 사용자 신원으로 변환한다.
   *
   * @param provider Token을 발급한 OAuth Provider
   * @param credential Provider별로 정규화된 Token
   * @return 검증된 Provider 사용자 신원
   * @throws BusinessException Credential 종류 불일치, Token 검증 실패 또는 Provider 장애인 경우
   */
  @Override
  public VerifiedOAuthIdentity verify(AuthProvider provider, OAuthProviderCredential credential) {
    requireCredentialType(provider, credential);
    if (provider == AuthProvider.GOOGLE) {
      return googleIdTokenVerifier.verify(credential.value());
    }
    if (provider == AuthProvider.APPLE) {
      return appleIdTokenVerifier.verify(credential.value(), credential.rawNonce());
    }
    try {
      return switch (provider) {
        case KAKAO -> verifyKakao(credential.value());
        case NAVER -> verifyNaver(credential.value());
        case GOOGLE -> throw new IllegalStateException("Google verification must be delegated");
        case APPLE -> throw new IllegalStateException("Apple verification must be delegated");
      };
    } catch (RestClientResponseException exception) {
      if (exception.getStatusCode().is4xxClientError()) {
        throw new BusinessException(AuthErrorCode.OAUTH_CREDENTIAL_INVALID, exception);
      }
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR, exception);
    } catch (RestClientException exception) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR, exception);
    }
  }

  private VerifiedOAuthIdentity verifyKakao(String accessToken) {
    String expectedAppId = requireKakaoAppId();
    KakaoTokenInfo tokenInfo = get(KAKAO_TOKEN_INFO_URI, accessToken, KakaoTokenInfo.class);
    if (tokenInfo == null
        || tokenInfo.id() == null
        || tokenInfo.appId() == null
        || tokenInfo.expiresIn() == null) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR);
    }
    if (tokenInfo.expiresIn() <= 0 || !expectedAppId.equals(tokenInfo.appId().toString())) {
      throw new BusinessException(AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    }

    KakaoUser response = get(KAKAO_USER_URI, accessToken, KakaoUser.class);
    if (response == null || response.id() == null) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR);
    }
    if (!tokenInfo.id().equals(response.id())) {
      throw new BusinessException(AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    }
    KakaoAccount account = response.kakaoAccount();
    String email =
        account != null
                && Boolean.TRUE.equals(account.emailValid())
                && Boolean.TRUE.equals(account.emailVerified())
            ? account.email()
            : null;
    return new VerifiedOAuthIdentity(AuthProvider.KAKAO, response.id().toString(), email);
  }

  private VerifiedOAuthIdentity verifyNaver(String accessToken) {
    NaverUser response = get(NAVER_USER_URI, accessToken, NaverUser.class);
    if (response == null || response.response() == null) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR);
    }
    if (!"00".equals(response.resultCode()) || !StringUtils.hasText(response.response().id())) {
      throw new BusinessException(AuthErrorCode.OAUTH_CREDENTIAL_INVALID);
    }
    return new VerifiedOAuthIdentity(
        AuthProvider.NAVER, response.response().id(), response.response().email());
  }

  private <T> T get(String uri, String accessToken, Class<T> responseType) {
    return restClient
        .get()
        .uri(uri)
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
        .retrieve()
        .body(responseType);
  }

  private String requireKakaoAppId() {
    OAuthProviderProperties.Kakao kakao = properties.kakao();
    if (kakao == null || !StringUtils.hasText(kakao.appId())) {
      throw new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    }
    return kakao.appId();
  }

  private void requireCredentialType(AuthProvider provider, OAuthProviderCredential credential) {
    OAuthCredentialType expected =
        provider == AuthProvider.GOOGLE || provider == AuthProvider.APPLE
            ? OAuthCredentialType.ID_TOKEN
            : OAuthCredentialType.ACCESS_TOKEN;
    if (credential.type() != expected) {
      throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID);
    }
  }

  private record KakaoTokenInfo(
      Long id, @JsonProperty("app_id") Long appId, @JsonProperty("expires_in") Integer expiresIn) {}

  private record KakaoUser(Long id, @JsonProperty("kakao_account") KakaoAccount kakaoAccount) {}

  private record KakaoAccount(
      String email,
      @JsonProperty("is_email_valid") Boolean emailValid,
      @JsonProperty("is_email_verified") Boolean emailVerified) {}

  private record NaverUser(@JsonProperty("resultcode") String resultCode, NaverProfile response) {}

  private record NaverProfile(String id, String email) {}
}
