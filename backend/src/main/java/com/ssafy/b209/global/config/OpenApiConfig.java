package com.ssafy.b209.global.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springdoc.core.models.GroupedOpenApi;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * OpenAPI 기본 정보와 API 그룹 구성을 제공한다.
 *
 * <p>각 Endpoint의 문서는 Controller가 담당하며, Swagger UI가 Access JWT를 전송할 수 있도록 Bearer Scheme을 제공한다.
 */
@Configuration
public class OpenApiConfig {

  /** Spring 컨테이너가 OpenAPI 관련 Bean 설정을 생성할 수 있도록 구성 객체를 만든다. */
  public OpenApiConfig() {}

  /**
   * 서비스의 공통 제목, 설명, 버전을 담은 기본 OpenAPI 문서를 만든다.
   *
   * @return 백엔드 REST API의 기본 정보를 포함하는 OpenAPI 객체
   */
  @Bean
  public OpenAPI openAPI() {
    return new OpenAPI()
        .addSecurityItem(new SecurityRequirement().addList("bearerAuth"))
        .components(
            new Components()
                .addSecuritySchemes(
                    "bearerAuth",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")))
        .info(
            new Info()
                .title("아동 그림·대화 기반 정서 지원 서비스 API")
                .description("백엔드 REST API 명세")
                .version("v1"));
  }

  /**
   * 외부 클라이언트용 {@code /api/v1/**} 경로만 포함하는 OpenAPI 그룹을 만든다.
   *
   * @return 이름이 {@code api-v1}인 버전 1 API 문서 그룹
   */
  @Bean
  public GroupedOpenApi apiV1Group() {
    return GroupedOpenApi.builder().group("api-v1").pathsToMatch("/api/v1/**").build();
  }
}
