package com.ssafy.b209.global.config;

import static org.assertj.core.api.Assertions.assertThat;

import io.swagger.v3.oas.models.OpenAPI;
import org.junit.jupiter.api.Test;
import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class OpenApiConfigTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner().withUserConfiguration(OpenApiConfig.class);

  @Test
  void providesOpenApiInfoAndApiV1Group() {
    contextRunner.run(
        context -> {
          OpenAPI openApi = context.getBean(OpenAPI.class);
          GroupedOpenApi groupedOpenApi = context.getBean(GroupedOpenApi.class);

          assertThat(openApi.getInfo().getTitle()).isEqualTo("아동 그림·대화 기반 정서 지원 서비스 API");
          assertThat(openApi.getInfo().getDescription()).isEqualTo("백엔드 REST API 명세");
          assertThat(openApi.getInfo().getVersion()).isEqualTo("v1");
          assertThat(openApi.getServers()).isNullOrEmpty();
          assertThat(openApi.getComponents().getSecuritySchemes()).containsKey("bearerAuth");
          assertThat(openApi.getComponents().getSecuritySchemes().get("bearerAuth").getScheme())
              .isEqualTo("bearer");
          assertThat(
                  openApi.getComponents().getSecuritySchemes().get("bearerAuth").getBearerFormat())
              .isEqualTo("JWT");

          assertThat(groupedOpenApi.getGroup()).isEqualTo("api-v1");
          assertThat(groupedOpenApi.getPathsToMatch()).containsExactly("/api/v1/**");
        });
  }
}
