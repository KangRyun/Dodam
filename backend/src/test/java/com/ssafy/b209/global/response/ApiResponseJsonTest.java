package com.ssafy.b209.global.response;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class ApiResponseJsonTest {

  private final ObjectMapper objectMapper = new ObjectMapper();

  @Test
  void serializesFieldsInContractOrder() throws Exception {
    ApiResponse<TestData> response = ApiResponse.ok(new TestData(1L, "test"));

    JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(response));

    List<String> fieldNames = new ArrayList<>();
    json.fieldNames().forEachRemaining(fieldNames::add);
    assertThat(fieldNames).containsExactly("success", "code", "message", "data");
    assertThat(json.get("success").isBoolean()).isTrue();
    assertThat(json.get("success").asBoolean()).isTrue();
    assertThat(json.get("code").isTextual()).isTrue();
    assertThat(json.get("code").asText()).isEqualTo("COMMON_200");
    assertThat(json.get("message").isTextual()).isTrue();
    assertThat(json.get("message").asText()).isEqualTo("요청이 성공했습니다.");
    assertThat(json.get("data").isObject()).isTrue();
    assertThat(json.get("data").get("id").asLong()).isEqualTo(1L);
    assertThat(json.get("data").get("name").asText()).isEqualTo("test");
  }

  @Test
  void keepsNullDataField() throws Exception {
    JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(ApiResponse.ok()));

    assertThat(json.has("data")).isTrue();
    assertThat(json.get("data").isNull()).isTrue();
  }

  @Test
  void serializesListAndEmptyList() throws Exception {
    JsonNode listJson =
        objectMapper.readTree(
            objectMapper.writeValueAsString(ApiResponse.ok(List.of(new TestData(1L, "first")))));
    JsonNode emptyListJson =
        objectMapper.readTree(objectMapper.writeValueAsString(ApiResponse.ok(List.of())));

    assertThat(listJson.get("data").isArray()).isTrue();
    assertThat(listJson.get("data").size()).isEqualTo(1);
    assertThat(listJson.get("data").get(0).get("name").asText()).isEqualTo("first");
    assertThat(emptyListJson.get("data").isArray()).isTrue();
    assertThat(emptyListJson.get("data").size()).isZero();
  }

  @Test
  void doesNotExposeHttpStatusOrEnumName() throws Exception {
    JsonNode json =
        objectMapper.readTree(
            objectMapper.writeValueAsString(
                ApiResponse.of(CommonSuccessCode.CREATED, new TestData(1L, "created"))));

    assertThat(json.has("httpStatus")).isFalse();
    assertThat(json.toString()).doesNotContain("CREATED");
    assertThat(json.get("code").asText()).isEqualTo("COMMON_201");
  }

  private record TestData(Long id, String name) {}
}
