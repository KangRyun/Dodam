package com.ssafy.b209.drawing.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.drawing.service.DrawingStageCompletionService;
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
class DrawingStageCompletionOpenApiTest {

  @Autowired private MockMvc mockMvc;
  @Autowired private ObjectMapper objectMapper;
  @MockitoBean private DrawingStageCompletionService service;

  @Test
  void documentsTheMultipartDrawingCompletionContract() throws Exception {
    JsonNode operation =
        apiDocument()
            .at("/paths/~1api~1v1~1drawing-sessions~1{drawingSessionId}~1drawing-complete/post");

    assertThat(operation.isMissingNode()).isFalse();
    assertThat(operation.path("tags"))
        .anySatisfy(tag -> assertThat(tag.asText()).isEqualTo("Drawing Sessions"));
    assertThat(operation.at("/requestBody/content/multipart~1form-data").isMissingNode()).isFalse();
    assertThat(operation.path("parameters"))
        .anySatisfy(
            parameter -> {
              assertThat(parameter.path("name").asText()).isEqualTo("Idempotency-Key");
              assertThat(parameter.path("in").asText()).isEqualTo("header");
              assertThat(parameter.path("required").asBoolean()).isTrue();
            });
    assertThat(operation.at("/requestBody/content/multipart~1form-data/schema/required"))
        .anySatisfy(required -> assertThat(required.asText()).isEqualTo("metadata"));
    assertThat(operation.path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("200", "400", "401", "404", "409", "413", "500"));
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
