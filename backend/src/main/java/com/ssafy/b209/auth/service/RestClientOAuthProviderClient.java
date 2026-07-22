package com.ssafy.b209.auth.service;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Objects;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

/** Kakao·Google·Naver REST API로 authorization code와 사용자 신원을 검증한다. */
@Component
public class RestClientOAuthProviderClient implements OAuthProviderClient {

  private static final String KAKAO_TOKEN_URI = "https://kauth.kakao.com/oauth/token";
  private static final String KAKAO_USER_URI = "https://kapi.kakao.com/v2/user/me";
  private static final String GOOGLE_TOKEN_URI = "https://oauth2.googleapis.com/token";
  private static final String GOOGLE_USER_URI = "https://openidconnect.googleapis.com/v1/userinfo";
  private static final String NAVER_TOKEN_URI = "https://nid.naver.com/oauth2.0/token";
  private static final String NAVER_USER_URI = "https://openapi.naver.com/v1/nid/me";

  private final RestClient restClient;
  private final OAuthProviderProperties properties;

  /**
   * Provider API Client를 구성한다.
   *
   * @param builder Spring이 제공하는 RestClient Builder
   * @param properties Provider별 Client와 통신 제한 시간 설정
   */
  @Autowired
  public RestClientOAuthProviderClient(
      RestClient.Builder builder, OAuthProviderProperties properties) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(properties.connectTimeout());
    requestFactory.setReadTimeout(properties.readTimeout());
    this.restClient = builder.requestFactory(requestFactory).build();
    this.properties = properties;
  }

  RestClientOAuthProviderClient(RestClient restClient, OAuthProviderProperties properties) {
    this.restClient = restClient;
    this.properties = properties;
  }

  @Override
  public VerifiedOAuthIdentity verify(AuthProvider provider, OAuthLoginRequest request) {
    OAuthProviderProperties.Provider providerConfig = requireConfiguration(provider, request);
    try {
      return switch (provider) {
        case KAKAO -> verifyKakao(request, providerConfig);
        case GOOGLE -> verifyGoogle(request, providerConfig);
        case NAVER -> verifyNaver(request, providerConfig);
      };
    } catch (RestClientResponseException exception) {
      if (exception.getStatusCode().is4xxClientError()) {
        throw new BusinessException(AuthErrorCode.OAUTH_CODE_INVALID, exception);
      }
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR, exception);
    } catch (RestClientException exception) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR, exception);
    }
  }

  private VerifiedOAuthIdentity verifyKakao(
      OAuthLoginRequest request, OAuthProviderProperties.Provider config) {
    MultiValueMap<String, String> form = commonTokenForm(request, config);
    addIfPresent(form, "client_secret", config.clientSecret());
    ProviderToken token = exchange(KAKAO_TOKEN_URI, form);
    KakaoUser response = get(KAKAO_USER_URI, token.accessToken(), KakaoUser.class);
    if (response == null || response.id() == null) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR);
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

  private VerifiedOAuthIdentity verifyGoogle(
      OAuthLoginRequest request, OAuthProviderProperties.Provider config) {
    MultiValueMap<String, String> form = commonTokenForm(request, config);
    form.add("client_secret", config.clientSecret());
    ProviderToken token = exchange(GOOGLE_TOKEN_URI, form);
    GoogleUser response = get(GOOGLE_USER_URI, token.accessToken(), GoogleUser.class);
    if (response == null || response.subject() == null || response.subject().isBlank()) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR);
    }
    String email = Boolean.TRUE.equals(response.emailVerified()) ? response.email() : null;
    return new VerifiedOAuthIdentity(AuthProvider.GOOGLE, response.subject(), email);
  }

  private VerifiedOAuthIdentity verifyNaver(
      OAuthLoginRequest request, OAuthProviderProperties.Provider config) {
    if (request.state() == null || request.state().isBlank()) {
      throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID);
    }
    MultiValueMap<String, String> form = commonTokenForm(request, config);
    form.add("client_secret", config.clientSecret());
    form.add("state", request.state());
    ProviderToken token = exchange(NAVER_TOKEN_URI, form);
    NaverUser response = get(NAVER_USER_URI, token.accessToken(), NaverUser.class);
    if (response == null
        || !"00".equals(response.resultCode())
        || response.response() == null
        || response.response().id() == null
        || response.response().id().isBlank()) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR);
    }
    return new VerifiedOAuthIdentity(AuthProvider.NAVER, response.response().id(), null);
  }

  private ProviderToken exchange(String uri, MultiValueMap<String, String> form) {
    ProviderToken token =
        restClient
            .post()
            .uri(uri)
            .contentType(MediaType.APPLICATION_FORM_URLENCODED)
            .body(form)
            .retrieve()
            .body(ProviderToken.class);
    if (token == null || token.accessToken() == null || token.accessToken().isBlank()) {
      throw new BusinessException(AuthErrorCode.OAUTH_PROVIDER_ERROR);
    }
    return token;
  }

  private <T> T get(String uri, String accessToken, Class<T> responseType) {
    return restClient
        .get()
        .uri(uri)
        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
        .retrieve()
        .body(responseType);
  }

  private OAuthProviderProperties.Provider requireConfiguration(
      AuthProvider provider, OAuthLoginRequest request) {
    OAuthProviderProperties.Provider config = properties.forProvider(provider);
    if (config == null
        || isBlank(config.clientId())
        || isBlank(config.redirectUri())
        || (provider != AuthProvider.KAKAO && isBlank(config.clientSecret()))) {
      throw new BusinessException(AuthErrorCode.AUTH_CONFIGURATION_INVALID);
    }
    if (!Objects.equals(config.redirectUri(), request.redirectUri())) {
      throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID);
    }
    return config;
  }

  private MultiValueMap<String, String> commonTokenForm(
      OAuthLoginRequest request, OAuthProviderProperties.Provider config) {
    MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
    form.add("grant_type", "authorization_code");
    form.add("client_id", config.clientId());
    form.add("redirect_uri", config.redirectUri());
    form.add("code", request.authorizationCode());
    return form;
  }

  private void addIfPresent(MultiValueMap<String, String> form, String name, String value) {
    if (!isBlank(value)) {
      form.add(name, value);
    }
  }

  private boolean isBlank(String value) {
    return value == null || value.isBlank();
  }

  private record ProviderToken(@JsonProperty("access_token") String accessToken) {}

  private record KakaoUser(Long id, @JsonProperty("kakao_account") KakaoAccount kakaoAccount) {}

  private record KakaoAccount(
      String email,
      @JsonProperty("is_email_valid") Boolean emailValid,
      @JsonProperty("is_email_verified") Boolean emailVerified) {}

  private record GoogleUser(
      @JsonProperty("sub") String subject,
      String email,
      @JsonProperty("email_verified") Boolean emailVerified) {}

  private record NaverUser(@JsonProperty("resultcode") String resultCode, NaverProfile response) {}

  private record NaverProfile(String id) {}
}
