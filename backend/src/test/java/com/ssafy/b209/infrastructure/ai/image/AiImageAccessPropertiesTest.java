package com.ssafy.b209.infrastructure.ai.image;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URI;
import java.time.Duration;
import org.junit.jupiter.api.Test;

class AiImageAccessPropertiesTest {

  @Test
  void normalizesTheInternalBaseUrlAndKeepsTheShortTtl() {
    AiImageAccessProperties properties =
        new AiImageAccessProperties(URI.create("http://backend:8080/"), Duration.ofSeconds(60));

    assertThat(properties.internalBaseUrl()).isEqualTo(URI.create("http://backend:8080"));
    assertThat(properties.tokenTtl()).isEqualTo(Duration.ofSeconds(60));
  }

  @Test
  void rejectsPublicOrInvalidConfiguration() {
    assertThatThrownBy(
            () ->
                new AiImageAccessProperties(
                    URI.create("https://example.com"), Duration.ofSeconds(60)))
        .isInstanceOf(IllegalArgumentException.class);
    assertThatThrownBy(
            () ->
                new AiImageAccessProperties(
                    URI.create("http://backend:8080"), Duration.ofMinutes(6)))
        .isInstanceOf(IllegalArgumentException.class);
    assertThatThrownBy(
            () ->
                new AiImageAccessProperties(
                    URI.create("http://backend:8080/base"), Duration.ofSeconds(60)))
        .isInstanceOf(IllegalArgumentException.class);
  }
}
