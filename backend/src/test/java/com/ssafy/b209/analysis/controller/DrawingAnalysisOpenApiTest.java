package com.ssafy.b209.analysis.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.analysis.service.DrawingAnalysisQueryService;
import com.ssafy.b209.analysis.service.DrawingAnalysisService;
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
class DrawingAnalysisOpenApiTest {

  @Autowired private MockMvc mockMvc;
  @Autowired private ObjectMapper objectMapper;
  @MockitoBean private DrawingAnalysisService drawingAnalysisService;
  @MockitoBean private DrawingAnalysisQueryService drawingAnalysisQueryService;

  @Test
  void documentsDrawingAnalysisCreationContract() throws Exception {
    JsonNode operation =
        apiDocument().at("/paths/~1api~1v1~1drawing-sessions~1{drawingSessionId}~1analyses/post");

    assertThat(operation.isMissingNode()).isFalse();
    assertThat(operation.path("tags"))
        .anySatisfy(tag -> assertThat(tag.asText()).isEqualTo("Drawing Analyses"));
    assertThat(operation.at("/requestBody/required").asBoolean()).isTrue();
    assertThat(operation.path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("201", "400", "404", "409", "500", "502"));
    assertThat(operation.has("security")).isFalse();
  }

  @Test
  void documentsDrawingAnalysisResultQueryContract() throws Exception {
    JsonNode operation =
        apiDocument()
            .at(
                "/paths/~1api~1v1~1drawing-sessions~1{drawingSessionId}~1analyses~1{drawingAnalysisId}/get");

    assertThat(operation.isMissingNode()).isFalse();
    assertThat(operation.path("tags"))
        .anySatisfy(tag -> assertThat(tag.asText()).isEqualTo("Drawing Analyses"));
    assertThat(operation.path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("200", "400", "404", "500"));
    assertThat(operation.has("security")).isFalse();
  }

  @Test
  void documentsFailedDrawingAnalysisRetryContract() throws Exception {
    JsonNode operation = apiDocument().at("/paths/~1api~1v1~1analyses~1{analysisId}~1retry/post");

    assertThat(operation.isMissingNode()).isFalse();
    assertThat(operation.path("tags"))
        .anySatisfy(tag -> assertThat(tag.asText()).isEqualTo("Drawing Analyses"));
    assertThat(operation.at("/requestBody/required").asBoolean()).isTrue();
    assertThat(operation.path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("201", "400", "404", "409", "502"));
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
