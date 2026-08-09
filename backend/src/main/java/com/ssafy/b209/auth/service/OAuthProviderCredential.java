package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import java.util.Objects;
import org.springframework.util.StringUtils;

/**
 * HTTP 요청에서 Provider 규칙에 맞게 선택한 단일 OAuth Token이다.
 *
 * <p>Provider Client가 HTTP DTO에 의존하지 않고 검증 대상의 종류와 값만 받도록 경계를 분리한다. Token 값은 저장하거나 로그에 기록하지 않는다.
 *
 * @param type 검증할 Token 종류
 * @param value Provider가 발급한 원본 Token
 * @param rawNonce Apple ID Token의 nonce Claim과 대조할 원본 nonce
 */
public record OAuthProviderCredential(OAuthCredentialType type, String value, String rawNonce) {

  OAuthProviderCredential(OAuthCredentialType type, String value) {
    this(type, value, null);
  }

  /**
   * 비어 있지 않은 Token Credential을 생성한다.
   *
   * @throws NullPointerException {@code type} 또는 {@code value}가 {@code null}인 경우
   * @throws IllegalArgumentException {@code value}가 공백인 경우
   */
  public OAuthProviderCredential {
    Objects.requireNonNull(type, "type must not be null");
    Objects.requireNonNull(value, "value must not be null");
    if (!StringUtils.hasText(value)) {
      throw new IllegalArgumentException("value must not be blank");
    }
  }

  /**
   * Provider별 허용 필드 조합을 검증하고 단일 Credential로 변환한다.
   *
   * @param provider 로그인을 요청한 OAuth Provider
   * @param request Provider Token 로그인 요청
   * @return Provider 검증 계층에 전달할 Credential
   * @throws BusinessException Token 누락·중복 또는 Provider와 Token 종류가 일치하지 않는 경우
   */
  public static OAuthProviderCredential from(AuthProvider provider, OAuthLoginRequest request) {
    boolean hasAccessToken = StringUtils.hasText(request.accessToken());
    boolean hasIdToken = StringUtils.hasText(request.idToken());
    if (hasAccessToken == hasIdToken) {
      throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID);
    }
    return switch (provider) {
      case KAKAO, NAVER -> {
        if (!hasAccessToken || StringUtils.hasText(request.rawNonce())) {
          throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID);
        }
        yield new OAuthProviderCredential(
            OAuthCredentialType.ACCESS_TOKEN, request.accessToken(), null);
      }
      case GOOGLE -> {
        if (!hasIdToken || StringUtils.hasText(request.rawNonce())) {
          throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID);
        }
        yield new OAuthProviderCredential(OAuthCredentialType.ID_TOKEN, request.idToken(), null);
      }
      case APPLE -> {
        if (!hasIdToken || !StringUtils.hasText(request.rawNonce())) {
          throw new BusinessException(AuthErrorCode.OAUTH_REQUEST_INVALID);
        }
        yield new OAuthProviderCredential(
            OAuthCredentialType.ID_TOKEN, request.idToken(), request.rawNonce());
      }
    };
  }
}
