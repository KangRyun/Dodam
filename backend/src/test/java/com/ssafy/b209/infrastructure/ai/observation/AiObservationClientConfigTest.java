package com.ssafy.b209.infrastructure.ai.observation;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;
import org.springframework.web.client.RestClient;

class AiObservationClientConfigTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner()
          .withUserConfiguration(AiObservationClientConfig.class, SupportConfig.class)
          .withPropertyValues(
              "app.ai.observation.base-url=http://127.0.0.1:1",
              "app.ai.observation.endpoint-path=/internal/v1/observations",
              "app.ai.observation.connect-timeout=3s",
              "app.ai.observation.read-timeout=30s");

  @Test
  void selectsMockClientWithoutCreatingHttpClient() {
    contextRunner
        .withPropertyValues("app.ai.observation.mode=mock")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).hasSingleBean(AiObservationClientProperties.class);
              assertThat(context).doesNotHaveBean(RestClient.class);
              assertThat(context).hasSingleBean(AiObservationClient.class);
              assertThat(context.getBean(AiObservationClient.class))
                  .isInstanceOf(MockAiObservationClient.class);
              assertThat(AiObservationClient.class).isInterface();
            });
  }

  @Test
  void selectsHttpClientWithoutCreatingMockClient() {
    contextRunner
        .withPropertyValues("app.ai.observation.mode=http", "AI_INTERNAL_TOKEN=internal-token")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).hasSingleBean(RestClient.class);
              assertThat(context).hasSingleBean(AiObservationClient.class);
              assertThat(context.getBean(AiObservationClient.class))
                  .isInstanceOf(RestClientAiObservationClient.class);
              assertThat(context).doesNotHaveBean(MockAiObservationClient.class);
            });
  }

  @Test
  void rejectsHttpClientWithoutInternalToken() {
    contextRunner
        .withPropertyValues("app.ai.observation.mode=http")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void rejectsUnsupportedClientMode() {
    contextRunner
        .withPropertyValues("app.ai.observation.mode=unknown")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void definesOnlySafeClientFailureTypes() {
    assertThat(AiObservationClientException.Type.values())
        .extracting(Enum::name)
        .containsExactly("REQUEST_FAILED", "TIMEOUT", "INVALID_RESPONSE", "SERVER_ERROR");
  }

  @Configuration(proxyBeanMethods = false)
  static class SupportConfig {

    @Bean
    RestClient.Builder restClientBuilder() {
      return RestClient.builder();
    }

    @Bean
    LocalValidatorFactoryBean validator() {
      return new LocalValidatorFactoryBean();
    }

    /** 응답 원문을 계약 스키마로 읽는 Mapper 다. 운영에서는 Boot 가 등록한 Bean 을 쓴다. */
    @Bean
    ObjectMapper objectMapper() {
      return new ObjectMapper();
    }
  }
}
