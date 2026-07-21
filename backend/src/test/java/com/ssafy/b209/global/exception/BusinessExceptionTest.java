package com.ssafy.b209.global.exception;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNullPointerException;

import com.ssafy.b209.global.response.CommonErrorCode;
import org.junit.jupiter.api.Test;

class BusinessExceptionTest {

  @Test
  void keepsErrorCodeAndSafeMessage() {
    BusinessException exception = new BusinessException(CommonErrorCode.RESOURCE_NOT_FOUND);

    assertThat(exception.getErrorCode()).isEqualTo(CommonErrorCode.RESOURCE_NOT_FOUND);
    assertThat(exception.getMessage()).isEqualTo("요청한 리소스를 찾을 수 없습니다.");
  }

  @Test
  void keepsCause() {
    RuntimeException cause = new RuntimeException("internal detail");

    BusinessException exception =
        new BusinessException(CommonErrorCode.INTERNAL_SERVER_ERROR, cause);

    assertThat(exception.getCause()).isSameAs(cause);
  }

  @Test
  void rejectsNullErrorCode() {
    assertThatNullPointerException()
        .isThrownBy(() -> new BusinessException(null))
        .withMessage("errorCode must not be null");
  }
}
