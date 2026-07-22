package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;
import org.springframework.web.client.RestClient;

class DrawingAnalysisClientConfigTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner()
          .withUserConfiguration(DrawingAnalysisClientConfig.class, RestClientBuilderConfig.class)
          .withPropertyValues(
              "app.ai.drawing-analysis.base-url=http://127.0.0.1:1",
              "app.ai.drawing-analysis.endpoint-path=/internal/ai/v1/drawings/analysis",
              "app.ai.drawing-analysis.connect-timeout=3s",
              "app.ai.drawing-analysis.read-timeout=30s");

  @Test
  void createsClientBoundaryAndRestClientWithoutNetworkCall() {
    contextRunner.run(
        context -> {
          assertThat(context).hasNotFailed();
          assertThat(context).hasSingleBean(DrawingAnalysisClientProperties.class);
          assertThat(context).hasSingleBean(RestClient.class);
          assertThat(context).hasSingleBean(DrawingAnalysisClient.class);
          assertThat(DrawingAnalysisClient.class).isInterface();
        });
  }

  @Test
  void definesOnlySafeClientFailureTypes() {
    assertThat(DrawingAnalysisClientException.Type.values())
        .extracting(Enum::name)
        .containsExactly("REQUEST_FAILED", "TIMEOUT", "INVALID_RESPONSE", "SERVER_ERROR");
  }

  @Configuration(proxyBeanMethods = false)
  static class RestClientBuilderConfig {

    @Bean
    RestClient.Builder restClientBuilder() {
      return RestClient.builder();
    }

    @Bean
    LocalValidatorFactoryBean validator() {
      return new LocalValidatorFactoryBean();
    }
  }
}
