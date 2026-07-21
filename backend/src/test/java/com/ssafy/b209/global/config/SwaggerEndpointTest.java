package com.ssafy.b209.global.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ssafy.b209.global.response.ApiErrorResponse;
import com.ssafy.b209.global.response.ApiResponse;
import com.ssafy.b209.global.response.CommonErrorCode;
import com.ssafy.b209.global.response.FieldErrorDetail;
import com.ssafy.b209.global.response.ValidationErrorData;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(SwaggerEndpointTest.TestSwaggerController.class)
class SwaggerEndpointTest {

  private static final Set<String> RESPONSE_PROPERTIES =
      Set.of("success", "code", "message", "data");
  private static final Set<String> FIELD_ERROR_PROPERTIES = Set.of("field", "message");
  private static final Set<String> VALIDATION_ERROR_PROPERTIES =
      Set.of("fieldErrors", "globalErrors");
  private static final List<String> INTERNAL_PROPERTIES =
      List.of(
          "httpStatus",
          "errorCode",
          "successCode",
          "stackTrace",
          "cause",
          "localizedMessage",
          "suppressed",
          "exception",
          "trace",
          "path",
          "timestamp");

  @Autowired private MockMvc mockMvc;

  @Autowired private ObjectMapper objectMapper;

  @Test
  void swaggerUiHtmlRedirectsToIndex() throws Exception {
    mockMvc
        .perform(get("/swagger-ui.html"))
        .andExpect(status().is3xxRedirection())
        .andExpect(redirectedUrl("/swagger-ui/index.html"));
  }

  @Test
  void swaggerUiIndexIsHtml() throws Exception {
    mockMvc
        .perform(get("/swagger-ui/index.html"))
        .andExpect(status().isOk())
        .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML));
  }

  @Test
  void defaultOpenApiDocumentIncludesMetadataAndPaths() throws Exception {
    mockMvc
        .perform(get("/v3/api-docs"))
        .andExpect(status().isOk())
        .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
        .andExpect(jsonPath("$.openapi").isNotEmpty())
        .andExpect(jsonPath("$.info.title").value("아동 그림·대화 기반 정서 지원 서비스 API"))
        .andExpect(jsonPath("$.paths").isNotEmpty());
  }

  @Test
  void apiV1DocumentIncludesOnlyApiV1Paths() throws Exception {
    mockMvc
        .perform(get("/v3/api-docs/api-v1"))
        .andExpect(status().isOk())
        .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
        .andExpect(jsonPath("$.paths['/api/v1/test/success']").exists())
        .andExpect(jsonPath("$.paths['/outside/test']").doesNotExist())
        .andExpect(jsonPath("$.paths['/swagger-ui.html']").doesNotExist())
        .andExpect(jsonPath("$.paths['/swagger-ui/index.html']").doesNotExist())
        .andExpect(jsonPath("$.paths['/v3/api-docs']").doesNotExist())
        .andExpect(jsonPath("$.paths['/v3/api-docs/api-v1']").doesNotExist());
  }

  @Test
  void schemaExposesOnlyThePublicCommonResponseProperties() throws Exception {
    JsonNode document = apiV1Document();

    assertThat(document.at("/paths/~1outside~1test").isMissingNode()).isTrue();

    assertSchemaProperties(responseSchema(document, "/api/v1/test/success"), RESPONSE_PROPERTIES);
    assertSchemaProperties(responseSchema(document, "/api/v1/test/error"), RESPONSE_PROPERTIES);
    assertSchemaProperties(
        responseSchema(document, "/api/v1/test/validation-error"), RESPONSE_PROPERTIES);
    assertSchemaProperties(componentSchema(document, "FieldErrorDetail"), FIELD_ERROR_PROPERTIES);
    assertSchemaProperties(
        componentSchema(document, "ValidationErrorData"), VALIDATION_ERROR_PROPERTIES);

    document
        .at("/components/schemas")
        .properties()
        .forEach(
            schema ->
                INTERNAL_PROPERTIES.forEach(
                    property ->
                        assertThat(schema.getValue().path("properties").has(property))
                            .as("schema %s must not expose %s", schema.getKey(), property)
                            .isFalse()));
  }

  @Test
  void schemaDescribesThePublicCommonResponseProperties() throws Exception {
    JsonNode document = apiV1Document();

    assertSchemaDescriptions(responseSchema(document, "/api/v1/test/success"), RESPONSE_PROPERTIES);
    assertSchemaDescriptions(responseSchema(document, "/api/v1/test/error"), RESPONSE_PROPERTIES);
    assertSchemaDescriptions(
        responseSchema(document, "/api/v1/test/validation-error"), RESPONSE_PROPERTIES);
    assertSchemaDescriptions(componentSchema(document, "FieldErrorDetail"), FIELD_ERROR_PROPERTIES);
    assertSchemaDescriptions(
        componentSchema(document, "ValidationErrorData"), VALIDATION_ERROR_PROPERTIES);
  }

  @Test
  void schemaUsesExactCommonResponseExamples() throws Exception {
    JsonNode document = apiV1Document();

    assertSchemaExamples(
        responseSchema(document, "/api/v1/test/success"),
        List.of("true", "COMMON_200", "요청이 성공했습니다."));
    assertSchemaExamples(
        responseSchema(document, "/api/v1/test/error"),
        List.of("false", "COMMON_400_001", "요청 값이 올바르지 않습니다."));
  }

  private JsonNode apiV1Document() throws Exception {
    String content =
        mockMvc
            .perform(get("/v3/api-docs/api-v1"))
            .andExpect(status().isOk())
            .andReturn()
            .getResponse()
            .getContentAsString();
    return objectMapper.readTree(content);
  }

  private JsonNode responseSchema(JsonNode document, String path) {
    Set<Map.Entry<String, JsonNode>> contentTypes =
        document
            .at(
                "/paths/"
                    + path.replace("~", "~0").replace("/", "~1")
                    + "/get/responses/200/content")
            .properties();
    assertThat(contentTypes).as("response %s must define content", path).isNotEmpty();
    JsonNode schema = contentTypes.iterator().next().getValue().path("schema");
    String reference = schema.path("$ref").asText();

    assertThat(reference).startsWith("#/components/schemas/");
    return componentSchema(document, reference.substring("#/components/schemas/".length()));
  }

  private JsonNode componentSchema(JsonNode document, String name) {
    JsonNode schema =
        document.at("/components/schemas/" + name.replace("~", "~0").replace("/", "~1"));

    assertThat(schema.isMissingNode()).as("schema %s must be present", name).isFalse();
    return schema;
  }

  private void assertSchemaProperties(JsonNode schema, Set<String> expectedProperties) {
    Set<String> propertyNames = new HashSet<>();
    schema.path("properties").fieldNames().forEachRemaining(propertyNames::add);

    assertThat(propertyNames).containsExactlyInAnyOrderElementsOf(expectedProperties);
  }

  private void assertSchemaDescriptions(JsonNode schema, Set<String> properties) {
    assertThat(schema.path("description").asText()).isNotBlank();
    properties.forEach(
        property ->
            assertThat(schema.path("properties").path(property).path("description").asText())
                .as("schema property %s must have a description", property)
                .isNotBlank());
  }

  private void assertSchemaExamples(JsonNode schema, List<String> expectedExamples) {
    assertThat(
            List.of(
                schema.path("properties").path("success").path("example").asText(),
                schema.path("properties").path("code").path("example").asText(),
                schema.path("properties").path("message").path("example").asText()))
        .containsExactlyElementsOf(expectedExamples);
  }

  @RestController
  static class TestSwaggerController {

    @GetMapping("/api/v1/test/success")
    ApiResponse<TestData> success() {
      return ApiResponse.ok(new TestData("example"));
    }

    @GetMapping("/api/v1/test/error")
    ApiErrorResponse<Void> error() {
      return ApiErrorResponse.of(CommonErrorCode.INVALID_INPUT_VALUE);
    }

    @GetMapping("/api/v1/test/validation-error")
    ApiErrorResponse<ValidationErrorData> validationError() {
      return ApiErrorResponse.of(
          CommonErrorCode.INVALID_INPUT_VALUE,
          new ValidationErrorData(
              List.of(new FieldErrorDetail("name", "must not be blank")), List.of()));
    }

    @GetMapping("/outside/test")
    String outside() {
      return "outside";
    }
  }

  private record TestData(String value) {}
}
