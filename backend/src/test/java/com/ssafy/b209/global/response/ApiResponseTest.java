package com.ssafy.b209.global.response;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class ApiResponseTest {

  @Test
  void createsOkResponseWithData() {
    TestData data = new TestData(1L, "test");

    ApiResponse<TestData> response = ApiResponse.ok(data);

    assertThat(response.success()).isTrue();
    assertThat(response.code()).isEqualTo("COMMON_200");
    assertThat(response.message()).isEqualTo("요청이 성공했습니다.");
    assertThat(response.data()).isEqualTo(data);
  }

  @Test
  void createsOkResponseWithoutData() {
    ApiResponse<Void> response = ApiResponse.ok();

    assertThat(response.success()).isTrue();
    assertThat(response.code()).isEqualTo("COMMON_200");
    assertThat(response.message()).isEqualTo("요청이 성공했습니다.");
    assertThat(response.data()).isNull();
  }

  @Test
  void createsResponseFromSuccessCode() {
    TestData data = new TestData(1L, "created");

    ApiResponse<TestData> response = ApiResponse.of(CommonSuccessCode.CREATED, data);

    assertThat(response.success()).isTrue();
    assertThat(response.code()).isEqualTo("COMMON_201");
    assertThat(response.message()).isEqualTo("리소스가 생성되었습니다.");
    assertThat(response.data()).isEqualTo(data);
    assertThat(CommonSuccessCode.CREATED.getHttpStatus()).isEqualTo(HttpStatus.CREATED);
  }

  @Test
  void rejectsNullSuccessCode() {
    assertThatNullPointerException()
        .isThrownBy(() -> ApiResponse.of(null, "data"))
        .withMessage("successCode must not be null");
  }

  private record TestData(Long id, String name) {}
}
