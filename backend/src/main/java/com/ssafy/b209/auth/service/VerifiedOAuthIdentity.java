package com.ssafy.b209.auth.service;

import com.ssafy.b209.auth.domain.AuthProvider;
import java.util.Locale;
import java.util.Objects;

/**
 * OAuth Provider 통신 계층이 서명과 응답을 검증한 뒤 Provisioning 계층에 전달하는 신원이다.
 *
 * <p>{@code providerEmail}은 계정 식별에 사용하지 않으며 Provider가 유효성을 보증한 경우에만 포함해야 한다.
 *
 * @param provider 신원을 검증한 OAuth Provider
 * @param providerSubject Provider가 발급한 불변 사용자 식별자
 * @param providerEmail Provider가 검증한 이메일 또는 제공되지 않은 경우 {@code null}
 */
public record VerifiedOAuthIdentity(
    AuthProvider provider, String providerSubject, String providerEmail) {

  /** 입력 경계에서 필수 식별자를 검사하고 이메일 표현을 정규화한다. */
  public VerifiedOAuthIdentity {
    Objects.requireNonNull(provider, "provider must not be null");
    if (providerSubject == null || providerSubject.isBlank()) {
      throw new IllegalArgumentException("providerSubject must not be blank");
    }
    providerSubject = providerSubject.trim();
    if (providerEmail != null) {
      providerEmail = providerEmail.trim().toLowerCase(Locale.ROOT);
      if (providerEmail.isEmpty()) {
        providerEmail = null;
      }
    }
  }
}
