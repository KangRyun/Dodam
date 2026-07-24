package com.ssafy.b209.infrastructure.ai.image;

import static org.assertj.core.api.Assertions.assertThat;

import java.security.SecureRandom;
import org.junit.jupiter.api.Test;

class SecureRandomAiImageAccessTokenGeneratorTest {

  @Test
  void generatesUrlSafeTokensWithAtLeast256BitsOfEntropy() {
    SecureRandomAiImageAccessTokenGenerator generator =
        new SecureRandomAiImageAccessTokenGenerator(new SecureRandom());

    String first = generator.generate();
    String second = generator.generate();

    assertThat(first).matches("[A-Za-z0-9_-]{43}");
    assertThat(second).matches("[A-Za-z0-9_-]{43}").isNotEqualTo(first);
  }
}
