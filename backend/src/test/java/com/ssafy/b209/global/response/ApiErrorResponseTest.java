package com.ssafy.b209.global.response;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.http.HttpStatus;

class ApiErrorResponseTest {

  @Test
  void createsErrorResponseWithoutData() {
    ApiErrorResponse<Void> response = ApiErrorResponse.of(CommonErrorCode.INVALID_INPUT_VALUE);

    assertThat(response.success()).isFalse();
    assertThat(response.code()).isEqualTo("COMMON_400_001");
    assertThat(response.message()).isEqualTo("요청 값이 올바르지 않습니다.");
    assertThat(response.data()).isNull();
  }

  @Test
  void createsErrorResponseWithValidationData() {
    ValidationErrorData data =
        new ValidationErrorData(
            List.of(new FieldErrorDetail("childName", "아동 이름은 필수입니다.")), List.of());

    ApiErrorResponse<ValidationErrorData> response =
        ApiErrorResponse.of(CommonErrorCode.INVALID_INPUT_VALUE, data);

    assertThat(response.data()).isSameAs(data);
  }

  @Test
  void rejectsNullErrorCode() {
    assertThatNullPointerException()
        .isThrownBy(() -> ApiErrorResponse.of(null))
        .withMessage("errorCode must not be null");
  }

  @Test
  void defensivelyCopiesValidationLists() {
    List<FieldErrorDetail> source = new ArrayList<>();
    ValidationErrorData data = new ValidationErrorData(source, List.of());

    source.add(new FieldErrorDetail("name", "invalid"));

    assertThat(data.fieldErrors()).isEmpty();
    assertThatThrownBy(() -> data.fieldErrors().add(new FieldErrorDetail("name", "invalid")))
        .isInstanceOf(UnsupportedOperationException.class);
  }

  @Test
  void rejectsNullValidationLists() {
    assertThatNullPointerException()
        .isThrownBy(() -> new ValidationErrorData(null, List.of()))
        .withMessage("fieldErrors must not be null");
    assertThatNullPointerException()
        .isThrownBy(() -> new ValidationErrorData(List.of(), null))
        .withMessage("globalErrors must not be null");
  }

  @ParameterizedTest
  @MethodSource("commonErrorCodes")
  void keepsCommonErrorCodeAndHttpStatusAligned(
      CommonErrorCode errorCode, HttpStatus httpStatus, String code) {
    assertThat(errorCode.getHttpStatus()).isEqualTo(httpStatus);
    assertThat(errorCode.getCode()).isEqualTo(code);
  }

  private static Stream<Arguments> commonErrorCodes() {
    return Stream.of(
        Arguments.of(CommonErrorCode.INVALID_INPUT_VALUE, HttpStatus.BAD_REQUEST, "COMMON_400_001"),
        Arguments.of(CommonErrorCode.INVALID_TYPE_VALUE, HttpStatus.BAD_REQUEST, "COMMON_400_002"),
        Arguments.of(
            CommonErrorCode.MESSAGE_NOT_READABLE, HttpStatus.BAD_REQUEST, "COMMON_400_003"),
        Arguments.of(
            CommonErrorCode.MISSING_REQUEST_PARAMETER, HttpStatus.BAD_REQUEST, "COMMON_400_004"),
        Arguments.of(CommonErrorCode.RESOURCE_NOT_FOUND, HttpStatus.NOT_FOUND, "COMMON_404_001"),
        Arguments.of(
            CommonErrorCode.METHOD_NOT_ALLOWED, HttpStatus.METHOD_NOT_ALLOWED, "COMMON_405_001"),
        Arguments.of(
            CommonErrorCode.DATA_INTEGRITY_VIOLATION, HttpStatus.CONFLICT, "COMMON_409_001"),
        Arguments.of(
            CommonErrorCode.INTERNAL_SERVER_ERROR,
            HttpStatus.INTERNAL_SERVER_ERROR,
            "COMMON_500_001"));
  }
}
