package com.ssafy.b209.child.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.child.service.ChildQueryService;
import com.ssafy.b209.conversation.service.TemporaryGuardianResolver;
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
class ChildOpenApiTest {

  @Autowired private MockMvc mockMvc;
  @Autowired private ObjectMapper objectMapper;
  @MockitoBean private ChildQueryService childQueryService;
  @MockitoBean private TemporaryGuardianResolver guardianResolver;

  @Test
  void documentsTheChildDetailLookupContractAndAccessTokenBoundary() throws Exception {
    JsonNode operation = apiDocument().at("/paths/~1api~1v1~1children~1{childId}/get");

    assertThat(operation.isMissingNode()).isFalse();
    assertThat(operation.path("tags"))
        .anySatisfy(tag -> assertThat(tag.asText()).isEqualTo("Children"));
    assertThat(operation.path("description").asText())
        .contains("연결된 활성 아동")
        .contains("상태를 변경하지 않습니다")
        .contains("Access Token");
    assertThat(operation.path("parameters"))
        .anySatisfy(
            parameter -> {
              assertThat(parameter.path("name").asText()).isEqualTo("childId");
              assertThat(parameter.path("in").asText()).isEqualTo("path");
              assertThat(parameter.path("required").asBoolean()).isTrue();
            })
        .noneMatch(
            parameter ->
                Set.of("Authorization", "X-Guardian-User-Id")
                    .contains(parameter.path("name").asText()));
    assertThat(operation.path("responses").fieldNames())
        .toIterable()
        .containsExactlyInAnyOrderElementsOf(Set.of("200", "400", "401", "404", "500"));
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
