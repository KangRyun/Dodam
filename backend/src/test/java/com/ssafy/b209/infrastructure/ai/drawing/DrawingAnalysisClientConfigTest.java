package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.ssafy.b209.infrastructure.ai.image.AiImageAccessConfig;
import com.ssafy.b209.infrastructure.ai.image.RedisDrawingAnalysisImageUrlProvider;
import com.ssafy.b209.storage.image.ImageStorage;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;
import org.springframework.web.client.RestClient;

class DrawingAnalysisClientConfigTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner()
          .withUserConfiguration(
              DrawingAnalysisClientConfig.class,
              AiImageAccessConfig.class,
              RestClientBuilderConfig.class)
          .withPropertyValues(
              "app.ai.drawing-analysis.base-url=http://127.0.0.1:1",
              "app.ai.drawing-analysis.endpoint-path=/internal/v1/analyses",
              "app.ai.drawing-analysis.connect-timeout=3s",
              "app.ai.drawing-analysis.read-timeout=30s",
              "app.ai.image-access.internal-base-url=http://backend:8080",
              "app.ai.image-access.token-ttl=60s");

  @Test
  void selectsMockClientByDefaultWithoutCreatingHttpClient() {
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.mode=mock")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).hasSingleBean(DrawingAnalysisClientProperties.class);
              assertThat(context).doesNotHaveBean(RestClient.class);
              assertThat(context).hasSingleBean(DrawingAnalysisClient.class);
              assertThat(context.getBean(DrawingAnalysisClient.class))
                  .isInstanceOf(MockDrawingAnalysisClient.class);
              assertThat(DrawingAnalysisClient.class).isInterface();
            });
  }

  @Test
  void selectsHttpClientWithoutCreatingMockClient() {
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.mode=http", "AI_INTERNAL_TOKEN=internal-token")
        .run(
            context -> {
              assertThat(context).hasNotFailed();
              assertThat(context).hasSingleBean(RestClient.class);
              assertThat(context).hasSingleBean(DrawingAnalysisClient.class);
              assertThat(context.getBean(DrawingAnalysisClient.class))
                  .isInstanceOf(RestClientDrawingAnalysisClient.class);
              assertThat(context).hasSingleBean(DrawingAnalysisImageUrlProvider.class);
              assertThat(context.getBean(DrawingAnalysisImageUrlProvider.class))
                  .isInstanceOf(RedisDrawingAnalysisImageUrlProvider.class);
              assertThat(context).doesNotHaveBean(MockDrawingAnalysisClient.class);
            });
  }

  @Test
  void rejectsHttpClientWithoutInternalToken() {
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.mode=http")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void rejectsUnsupportedClientMode() {
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.mode=unknown")
        .run(context -> assertThat(context).hasFailed());
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

    @Bean
    Clock clock() {
      return Clock.fixed(Instant.parse("2026-07-22T05:00:00Z"), ZoneOffset.UTC);
    }

    @Bean
    StringRedisTemplate stringRedisTemplate() {
      return mock(StringRedisTemplate.class);
    }

    @Bean
    ImageStorage imageStorage() {
      return mock(ImageStorage.class);
    }
  }
}
