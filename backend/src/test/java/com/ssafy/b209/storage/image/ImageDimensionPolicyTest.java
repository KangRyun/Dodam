package com.ssafy.b209.storage.image;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.ssafy.b209.global.exception.BusinessException;
import org.junit.jupiter.api.Test;

class ImageDimensionPolicyTest {

  @Test
  void acceptsMinimumAndMaximumBoundaryDimensions() {
    assertThatCode(() -> ImageDimensionPolicy.validate(320, 320)).doesNotThrowAnyException();
    assertThatCode(() -> ImageDimensionPolicy.validate(8192, 8192)).doesNotThrowAnyException();
  }

  @Test
  void rejectsDimensionsBelowTheMinimum() {
    assertDimensionError(() -> ImageDimensionPolicy.validate(319, 320));
    assertDimensionError(() -> ImageDimensionPolicy.validate(320, 319));
  }

  @Test
  void rejectsDimensionsAboveTheMaximum() {
    assertDimensionError(() -> ImageDimensionPolicy.validate(8193, 8192));
    assertDimensionError(() -> ImageDimensionPolicy.validate(8192, 8193));
  }

  private void assertDimensionError(Runnable action) {
    assertThatThrownBy(action::run)
        .isInstanceOfSatisfying(
            BusinessException.class,
            exception ->
                assertThat(exception.getErrorCode())
                    .isEqualTo(ImageStorageErrorCode.IMAGE_DIMENSION_INVALID));
  }
}
