package com.ssafy.b209.global.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import io.swagger.v3.oas.models.tags.Tag;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.springdoc.core.customizers.OpenApiCustomizer;
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

  /**
   * MVP 시연 그리기 루프 순서대로 표시할 태그 목록이다.
   *
   * <p>Swagger UI는 OpenAPI 문서의 최상위 {@code tags} 배열 순서를 그대로 표시하므로, 시연 흐름(인증 → 아동 → 그림 세션 → 스트로크 →
   * 스냅샷 → 그림 분석 → 대화 → 회고 → 완료) 순으로 나열한다. 이름은 Controller가 이미 사용 중인 태그 이름과 동일하게 유지해 태그가 분리되지 않게 한다.
   */
  private static final List<Tag> MVP_FLOW_TAGS =
      List.of(
          new Tag().name("Authentication").description("인증 · OAuth 로그인 (시연 1단계)"),
          new Tag().name("Children").description("아동 프로필 (시연 2단계)"),
          new Tag().name("Drawing Sessions").description("그림 활동 세션 생성·조회·완료 (시연 3·14단계)"),
          new Tag().name("Drawing Strokes").description("스트로크 배치 저장 (시연 4단계)"),
          new Tag().name("Drawing Snapshots").description("최종 스냅샷 업로드 (시연 5단계)"),
          new Tag().name("Drawing Analyses").description("그림 분석 요청·조회 (시연 6·7단계)"),
          new Tag().name("Conversations").description("AI 대화 시작·질문·답변·내역 (시연 8~11단계)"),
          new Tag().name("Drawing Reflections").description("회고 저장 (시연 12단계)"),
          new Tag().name("Drawing Completions").description("완료 접수 (시연 13단계)"));

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

  /**
   * MVP 시연 흐름 순서로 Swagger UI의 태그 표시 순서를 정렬한다.
   *
   * <p>Controller가 선언한 기존 태그(설명 포함)를 흐름 순서 앞쪽으로 재배치하고, 문서에 아직 없는 흐름 태그는 한국어 설명으로 채운다. 흐름에 속하지 않는
   * 나머지 태그는 원래 순서를 유지한 채 뒤에 둔다. 이 커스터마이저는 태그 순서와 설명만 조정하며 Endpoint 동작에는 영향을 주지 않는다.
   *
   * @return 최상위 태그 배열을 시연 흐름 순으로 재정렬하는 커스터마이저
   */
  @Bean
  public OpenApiCustomizer mvpFlowTagOrderCustomizer() {
    return openApi -> {
      List<Tag> discovered =
          openApi.getTags() == null ? new ArrayList<>() : new ArrayList<>(openApi.getTags());
      List<Tag> ordered = new ArrayList<>();
      Set<String> placed = new LinkedHashSet<>();
      for (Tag flowTag : MVP_FLOW_TAGS) {
        Tag existing = findTagByName(discovered, flowTag.getName());
        ordered.add(existing == null ? flowTag : existing);
        placed.add(flowTag.getName());
      }
      for (Tag tag : discovered) {
        if (!placed.contains(tag.getName())) {
          ordered.add(tag);
        }
      }
      openApi.setTags(ordered);
    };
  }

  private static Tag findTagByName(List<Tag> tags, String name) {
    for (Tag tag : tags) {
      if (name.equals(tag.getName())) {
        return tag;
      }
    }
    return null;
  }
}
