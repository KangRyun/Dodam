package com.ssafy.b209.infrastructure.ai.drawing;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.autoconfigure.context.ConfigurationPropertiesAutoConfiguration;
import org.springframework.boot.autoconfigure.validation.ValidationAutoConfiguration;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.ConfigDataApplicationContextInitializer;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

class DrawingAnalysisClientPropertiesTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner()
          .withInitializer(new ConfigDataApplicationContextInitializer())
          .withConfiguration(
              AutoConfigurations.of(
                  ConfigurationPropertiesAutoConfiguration.class,
                  ValidationAutoConfiguration.class))
          .withUserConfiguration(PropertiesTestConfig.class);

  @Test
  void bindsDefaultDrawingAnalysisClientProperties() {
    contextRunner.run(
        context -> {
          assertThat(context).hasNotFailed();
          DrawingAnalysisClientProperties properties =
              context.getBean(DrawingAnalysisClientProperties.class);
          assertThat(properties.mode()).isEqualTo("mock");
          assertThat(properties.baseUrl().toString()).isEqualTo("http://localhost:8000");
          assertThat(properties.endpointPath()).isEqualTo("/internal/v1/analyses");
          assertThat(properties.connectTimeout()).isEqualTo(Duration.ofSeconds(3));
          assertThat(properties.readTimeout()).isEqualTo(Duration.ofSeconds(30));
        });
  }

  @Test
  void rejectsUnsupportedClientMode() {
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.mode=unknown")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void rejectsNonHttpBaseUrl() {
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.base-url=ftp://ai.internal")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void rejectsEndpointPathThatIsAnAbsoluteUrl() {
    contextRunner
        .withPropertyValues(
            "app.ai.drawing-analysis.endpoint-path=http://ai.internal/drawing-analysis")
        .run(context -> assertThat(context).hasFailed());
  }

  @Test
  void rejectsNonPositiveTimeouts() {
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.connect-timeout=0s")
        .run(context -> assertThat(context).hasFailed());
    contextRunner
        .withPropertyValues("app.ai.drawing-analysis.read-timeout=-1s")
        .run(context -> assertThat(context).hasFailed());
  }

  @Configuration(proxyBeanMethods = false)
  @EnableConfigurationProperties(DrawingAnalysisClientProperties.class)
  static class PropertiesTestConfig {}
}
