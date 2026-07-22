package com.ssafy.b209.conversation.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.conversation.exception.ConversationStartErrorCode;
import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.Test;

class GuardianUserResolverTest {

  @Test
  void temporaryResolverRejectsRequestWithoutBearerAndGuardianHeaders() {
    TemporaryGuardianResolver resolver = new TemporaryGuardianResolver();

    assertUnauthorized(() -> resolver.resolve(null, null));
  }

  @Test
  void productionGuardRejectsUnverifiedBearerAndTemporaryGuardianHeader() {
    UnavailableProductionGuardianResolver resolver = new UnavailableProductionGuardianResolver();

    assertUnauthorized(() -> resolver.resolve("Bearer unverified", "9"));
  }

  private void assertUnauthorized(Runnable action) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                org.assertj.core.api.Assertions.assertThat(exception.getErrorCode())
                    .isEqualTo(ConversationStartErrorCode.UNAUTHORIZED));
  }
}
