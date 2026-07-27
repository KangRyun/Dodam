package com.ssafy.b209.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.auth.domain.AuthProvider;
import com.ssafy.b209.auth.dto.request.OAuthLoginRequest;
import com.ssafy.b209.auth.exception.AuthErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.Test;

class OAuthProviderCredentialTest {

  @Test
  void createsAppleIdTokenCredentialWithRawNonce() {
    OAuthLoginRequest request =
        new OAuthLoginRequest(null, "apple-id-token", "raw-nonce", "device-1");

    OAuthProviderCredential credential = OAuthProviderCredential.from(AuthProvider.APPLE, request);

    assertThat(credential.type()).isEqualTo(OAuthCredentialType.ID_TOKEN);
    assertThat(credential.value()).isEqualTo("apple-id-token");
    assertThat(credential.rawNonce()).isEqualTo("raw-nonce");
  }

  @Test
  void rejectsAppleCredentialWithoutRawNonce() {
    OAuthLoginRequest request = new OAuthLoginRequest(null, "apple-id-token", null, "device-1");

    assertThatThrownBy(() -> OAuthProviderCredential.from(AuthProvider.APPLE, request))
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(AuthErrorCode.OAUTH_REQUEST_INVALID));
  }
}
