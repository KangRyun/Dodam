package com.ssafy.b209.global.response;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class ApiErrorResponseJsonTest {

  private final ObjectMapper objectMapper = new ObjectMapper();

  @Test
  void serializesErrorContractWithoutInternalInformation() throws Exception {
    ApiErrorResponse<Void> response = ApiErrorResponse.of(CommonErrorCode.INTERNAL_SERVER_ERROR);

    JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(response));

    List<String> fieldNames = new ArrayList<>();
    json.fieldNames().forEachRemaining(fieldNames::add);
    assertThat(fieldNames).containsExactly("success", "code", "message", "data");
    assertThat(json.get("success").isBoolean()).isTrue();
    assertThat(json.get("success").asBoolean()).isFalse();
    assertThat(json.get("code").asText()).isEqualTo("COMMON_500_001");
    assertThat(json.get("message").asText()).isEqualTo("서버 내부 오류가 발생했습니다.");
    assertThat(json.has("data")).isTrue();
    assertThat(json.get("data").isNull()).isTrue();
    assertThat(json.has("httpStatus")).isFalse();
    assertThat(json.has("exception")).isFalse();
    assertThat(json.has("trace")).isFalse();
    assertThat(json.toString()).doesNotContain("INTERNAL_SERVER_ERROR");
  }

  @Test
  void serializesValidationDetailsWithoutRejectedValue() throws Exception {
    ValidationErrorData data =
        new ValidationErrorData(
            List.of(new FieldErrorDetail("childName", "아동 이름은 필수입니다.")), List.of());
    ApiErrorResponse<ValidationErrorData> response =
        ApiErrorResponse.of(CommonErrorCode.INVALID_INPUT_VALUE, data);

    JsonNode json = objectMapper.readTree(objectMapper.writeValueAsString(response));

    assertThat(json.get("data").get("fieldErrors").isArray()).isTrue();
    assertThat(json.get("data").get("fieldErrors").size()).isEqualTo(1);
    assertThat(json.at("/data/fieldErrors/0/field").asText()).isEqualTo("childName");
    assertThat(json.at("/data/fieldErrors/0/message").asText()).isEqualTo("아동 이름은 필수입니다.");
    assertThat(json.get("data").get("globalErrors").isArray()).isTrue();
    assertThat(json.get("data").get("globalErrors").size()).isZero();
    assertThat(json.toString()).doesNotContain("rejectedValue", "secret-input");
  }
}
