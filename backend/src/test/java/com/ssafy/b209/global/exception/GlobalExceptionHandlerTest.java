package com.ssafy.b209.global.exception;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.ssafy.b209.global.response.CommonErrorCode;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.validation.BindException;
import org.springframework.validation.FieldError;
import org.springframework.validation.ObjectError;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@WebMvcTest(controllers = GlobalExceptionHandlerTest.TestExceptionController.class)
@Import({GlobalExceptionHandler.class, GlobalExceptionHandlerTest.TestExceptionController.class})
@ExtendWith(OutputCaptureExtension.class)
class GlobalExceptionHandlerTest {

  @Autowired private MockMvc mockMvc;

  @Test
  void handlesBusinessException() throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/business")),
        HttpStatus.NOT_FOUND,
        "COMMON_404_001",
        "요청한 리소스를 찾을 수 없습니다.");
  }

  @Test
  void handlesAuthenticationExceptionWithCommonUnauthorizedResponse() throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/authentication")),
        HttpStatus.UNAUTHORIZED,
        "AUTH_401_006",
        "인증이 필요합니다.");
  }

  @Test
  void handlesAccessDeniedExceptionWithCommonForbiddenResponse() throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/access-denied")),
        HttpStatus.FORBIDDEN,
        "AUTH_403_002",
        "요청한 작업에 대한 권한이 없습니다.");
  }

  @Test
  void handlesServerBusinessExceptionWithoutCauseMessage(CapturedOutput output) throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/business-server")),
        HttpStatus.INTERNAL_SERVER_ERROR,
        "COMMON_500_001",
        "서버 내부 오류가 발생했습니다.");

    assertThat(output)
        .contains("ERROR", "COMMON_500_001", "GlobalExceptionHandlerTest")
        .doesNotContain("token=secret");
  }

  @Test
  void handlesRequestBodyValidation() throws Exception {
    mockMvc
        .perform(
            post("/test/errors/body-validation")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"childName\":\"\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.success").value(false))
        .andExpect(jsonPath("$.code").value("COMMON_400_001"))
        .andExpect(jsonPath("$.data.fieldErrors[0].field").value("childName"))
        .andExpect(jsonPath("$.data.fieldErrors[0].message").value("아동 이름은 필수입니다."))
        .andExpect(jsonPath("$.data.globalErrors").isArray())
        .andExpect(jsonPath("$.rejectedValue").doesNotExist())
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("TestRequest"))));
  }

  @Test
  void handlesModelAttributeValidation() throws Exception {
    mockMvc
        .perform(get("/test/errors/bind-validation").param("name", ""))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.success").value(false))
        .andExpect(jsonPath("$.code").value("COMMON_400_001"))
        .andExpect(jsonPath("$.data.fieldErrors[0].field").value("name"))
        .andExpect(jsonPath("$.data.fieldErrors[0].message").value("이름은 필수입니다."));
  }

  @Test
  void returnsStableSafeFieldAndGlobalErrors() throws Exception {
    mockMvc
        .perform(get("/test/errors/binding-result"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.data.fieldErrors.length()").value(2))
        .andExpect(jsonPath("$.data.fieldErrors[0].field").value("aField"))
        .andExpect(jsonPath("$.data.fieldErrors[1].field").value("zField"))
        .andExpect(jsonPath("$.data.globalErrors.length()").value(2))
        .andExpect(jsonPath("$.data.globalErrors[0]").value("global a"))
        .andExpect(jsonPath("$.data.globalErrors[1]").value("global z"))
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("sensitive-input"))))
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("InternalDto"))));
  }

  @Test
  void handlesConstraintViolation() throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/constraint")),
        HttpStatus.BAD_REQUEST,
        "COMMON_400_001",
        "요청 값이 올바르지 않습니다.");
  }

  @Test
  void handlesHandlerMethodValidation() throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/method-validation").param("count", "0")),
        HttpStatus.BAD_REQUEST,
        "COMMON_400_001",
        "요청 값이 올바르지 않습니다.");
  }

  @Test
  void handlesReturnValueValidationAsServerError(CapturedOutput output) throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/return-validation")),
        HttpStatus.INTERNAL_SERVER_ERROR,
        "COMMON_500_001",
        "서버 내부 오류가 발생했습니다.");

    assertThat(output).contains("ERROR", "COMMON_500_001");
  }

  @Test
  void handlesTypeMismatch() throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/type/not-a-number")),
        HttpStatus.BAD_REQUEST,
        "COMMON_400_002",
        "요청 값의 형식이 올바르지 않습니다.");
  }

  @Test
  void handlesUnreadableJson() throws Exception {
    expectError(
            mockMvc.perform(
                post("/test/errors/json")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{invalid-json")),
            HttpStatus.BAD_REQUEST,
            "COMMON_400_003",
            "요청 본문을 읽을 수 없습니다.")
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("JsonParseException"))));
  }

  @Test
  void handlesMissingRequestParameter() throws Exception {
    expectError(
        mockMvc.perform(get("/test/errors/required")),
        HttpStatus.BAD_REQUEST,
        "COMMON_400_004",
        "필수 요청 파라미터가 누락되었습니다.");
  }

  @Test
  void handlesMissingMultipartRequestPart() throws Exception {
    expectError(
        mockMvc.perform(multipart("/test/errors/required-part")),
        HttpStatus.BAD_REQUEST,
        "COMMON_400_004",
        "필수 요청 파라미터가 누락되었습니다.");
  }

  @Test
  void handlesMethodNotAllowedAndPreservesAllowHeader() throws Exception {
    expectError(
            mockMvc.perform(post("/test/errors/method")),
            HttpStatus.METHOD_NOT_ALLOWED,
            "COMMON_405_001",
            "지원하지 않는 HTTP 메서드입니다.")
        .andExpect(header().string("Allow", "GET"));
  }

  @Test
  void handlesMissingResource() throws Exception {
    expectError(
            mockMvc.perform(get("/test/errors/not-found")),
            HttpStatus.NOT_FOUND,
            "COMMON_404_001",
            "요청한 리소스를 찾을 수 없습니다.")
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("/private/path"))))
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("NoResourceFoundException"))));
  }

  @Test
  void handlesDataIntegrityViolationWithoutDatabaseDetails(CapturedOutput output) throws Exception {
    expectError(
            mockMvc.perform(get("/test/errors/integrity")),
            HttpStatus.CONFLICT,
            "COMMON_409_001",
            "요청이 현재 데이터 상태와 충돌합니다.")
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("SQL constraint secret"))));

    assertThat(output).contains("WARN", "COMMON_409_001").doesNotContain("SQL constraint secret");
  }

  @Test
  void handlesUnexpectedExceptionWithoutInternalDetails(CapturedOutput output) throws Exception {
    expectError(
            mockMvc.perform(get("/test/errors/unexpected")),
            HttpStatus.INTERNAL_SERVER_ERROR,
            "COMMON_500_001",
            "서버 내부 오류가 발생했습니다.")
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("password=secret"))))
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("IllegalStateException"))));

    assertThat(output)
        .contains("ERROR", "COMMON_500_001", "GlobalExceptionHandlerTest")
        .doesNotContain("password=secret");
  }

  private ResultActions expectError(
      ResultActions resultActions, HttpStatus status, String code, String message)
      throws Exception {
    return resultActions
        .andExpect(status().is(status.value()))
        .andExpect(jsonPath("$.success").value(false))
        .andExpect(jsonPath("$.code").value(code))
        .andExpect(jsonPath("$.message").value(message))
        .andExpect(jsonPath("$.data").value(nullValue()))
        .andExpect(jsonPath("$.httpStatus").doesNotExist())
        .andExpect(jsonPath("$.exception").doesNotExist())
        .andExpect(jsonPath("$.trace").doesNotExist())
        .andExpect(jsonPath("$.path").doesNotExist())
        .andExpect(jsonPath("$.timestamp").doesNotExist());
  }

  @RestController
  @RequestMapping("/test/errors")
  public static class TestExceptionController {

    @GetMapping("/business")
    void business() {
      throw new BusinessException(CommonErrorCode.RESOURCE_NOT_FOUND);
    }

    @GetMapping("/business-server")
    void businessServer() {
      throw new BusinessException(
          CommonErrorCode.INTERNAL_SERVER_ERROR, new IllegalStateException("token=secret"));
    }

    @GetMapping("/authentication")
    void authentication() {
      throw new BadCredentialsException("sensitive authentication detail");
    }

    @GetMapping("/access-denied")
    void accessDenied() {
      throw new AccessDeniedException("sensitive authorization detail");
    }

    @PostMapping("/body-validation")
    void bodyValidation(@Valid @RequestBody TestRequest request) {}

    @GetMapping("/bind-validation")
    void bindValidation(@Valid @ModelAttribute TestQuery query) {}

    @GetMapping("/binding-result")
    void bindingResult() throws BindException {
      BindException exception = new BindException(new Object(), "InternalDto");
      exception.addError(
          new FieldError(
              "InternalDto", "zField", "sensitive-input", false, null, null, "z message"));
      exception.addError(
          new FieldError(
              "InternalDto", "aField", "sensitive-input", false, null, null, "a message"));
      exception.addError(
          new FieldError(
              "InternalDto", "aField", "sensitive-input", false, null, null, "a message"));
      exception.addError(new ObjectError("InternalDto", "global z"));
      exception.addError(new ObjectError("InternalDto", "global a"));
      exception.addError(new ObjectError("InternalDto", "global a"));
      throw exception;
    }

    @GetMapping("/constraint")
    void constraint() {
      throw new ConstraintViolationException(Set.of());
    }

    @GetMapping("/method-validation")
    void methodValidation(
        @RequestParam(name = "count") @Min(value = 1, message = "count는 1 이상이어야 합니다.") int count) {}

    @GetMapping("/return-validation")
    @Min(value = 1, message = "반환값은 1 이상이어야 합니다.")
    int returnValidation() {
      return 0;
    }

    @GetMapping("/type/{id}")
    void type(@PathVariable Long id) {}

    @PostMapping("/json")
    void json(@RequestBody TestRequest request) {}

    @GetMapping("/required")
    void required(@RequestParam String value) {}

    @PostMapping(value = "/required-part", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    void requiredPart(@RequestPart MultipartFile file) {}

    @GetMapping("/method")
    void method() {}

    @GetMapping("/not-found")
    void notFound() throws NoResourceFoundException {
      throw new NoResourceFoundException(HttpMethod.GET, "/private/path");
    }

    @GetMapping("/integrity")
    void integrity() {
      throw new DataIntegrityViolationException("SQL constraint secret");
    }

    @GetMapping("/unexpected")
    void unexpected() {
      throw new IllegalStateException("password=secret");
    }
  }

  record TestRequest(@NotBlank(message = "아동 이름은 필수입니다.") String childName) {}

  public static class TestQuery {

    @NotBlank(message = "이름은 필수입니다.")
    private String name;

    public String getName() {
      return name;
    }

    public void setName(String name) {
      this.name = name;
    }
  }
}
