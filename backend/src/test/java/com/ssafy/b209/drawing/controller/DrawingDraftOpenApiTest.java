package com.ssafy.b209.drawing.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.drawing.service.DrawingDraftService;
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
class DrawingDraftOpenApiTest {

  @Autowired private MockMvc mockMvc;
  @Autowired private ObjectMapper objectMapper;
  @MockitoBean private DrawingDraftService drawingDraftService;

  @Test
  void documentsDraftSaveLookupAndDeletionContract() throws Exception {
    JsonNode path =
        apiDocument().at("/paths/~1api~1v1~1drawing-sessions~1{drawingSessionId}~1draft");

    assertThat(path.path("put").isMissingNode()).isFalse();
    assertThat(path.path("get").isMissingNode()).isFalse();
    assertThat(path.path("delete").isMissingNode()).isFalse();
    assertThat(path.at("/put/requestBody/content/multipart~1form-data").isMissingNode()).isFalse();
    assertThat(path.path("put").path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("200", "400", "404", "409", "413", "500"));
    assertThat(path.path("get").path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("200", "400", "404"));
    assertThat(path.path("delete").path("responses").fieldNames())
        .toIterable()
        .containsAll(Set.of("204", "400", "404"));
    assertThat(path.path("put").has("security")).isFalse();
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
