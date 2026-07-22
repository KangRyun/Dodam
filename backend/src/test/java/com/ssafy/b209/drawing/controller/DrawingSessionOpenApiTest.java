package com.ssafy.b209.drawing.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.drawing.service.DrawingSessionQueryService;
import com.ssafy.b209.drawing.service.DrawingSessionService;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class DrawingSessionOpenApiTest {

  @Autowired private MockMvc mockMvc;
  @Autowired private ObjectMapper objectMapper;
  @MockitoBean private DrawingSessionService drawingSessionService;
  @MockitoBean private DrawingSessionQueryService drawingSessionQueryService;

  @Test
  void documentsCreationContractWithoutUnimplementedAuthentication() throws Exception {
    JsonNode operation = apiDocument().at("/paths/~1api~1v1~1drawing-sessions/post");

    assertThat(operation.isMissingNode()).isFalse();
    assertThat(operation.path("tags"))
        .anySatisfy(tag -> assertThat(tag.asText()).isEqualTo("Drawing Sessions"));
    assertThat(operation.path("parameters"))
        .anySatisfy(
            parameter -> {
              assertThat(parameter.path("name").asText()).isEqualTo("Idempotency-Key");
              assertThat(parameter.path("in").asText()).isEqualTo("header");
              assertThat(parameter.path("required").asBoolean()).isTrue();
            });
    assertThat(operation.at("/requestBody/required").asBoolean()).isTrue();
    assertThat(operation.path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("201", "400", "404", "409", "500"));
    assertThat(operation.has("security")).isFalse();
  }

  @Test
  void documentsActiveSessionLookupWithoutUnimplementedAuthentication() throws Exception {
    JsonNode operation = apiDocument().at("/paths/~1api~1v1~1drawing-sessions~1active/get");

    assertThat(operation.isMissingNode()).isFalse();
    assertThat(operation.path("tags"))
        .anySatisfy(tag -> assertThat(tag.asText()).isEqualTo("Drawing Sessions"));
    assertThat(operation.path("description").asText())
        .contains("최신 초안이 없을 수 있습니다")
        .contains("세션 상태를 변경하지 않습니다")
        .contains("AI 분석을 실행하지 않습니다")
        .contains("이미지 파일 다운로드 API가 아닙니다");
    assertThat(operation.path("parameters"))
        .singleElement()
        .satisfies(
            parameter -> {
              assertThat(parameter.path("name").asText()).isEqualTo("childId");
              assertThat(parameter.path("in").asText()).isEqualTo("query");
              assertThat(parameter.path("required").asBoolean()).isTrue();
            });
    assertThat(operation.path("responses").fieldNames())
        .toIterable()
        .containsExactlyInAnyOrder("200", "400", "404", "500");
    assertThat(operation.has("security")).isFalse();
  }

  private JsonNode apiDocument() throws Exception {
    String content =
        mockMvc
            .perform(get("/v3/api-docs/api-v1"))
            .andExpect(status().isOk())
            .andReturn()
            .getResponse()
            .getContentAsString();
    return objectMapper.readTree(content);
  }
}
