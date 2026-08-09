package com.ssafy.b209.storage.image;

import com.ssafy.b209.global.exception.BusinessException;

/**
 * 그림 이미지 저장에 허용되는 픽셀 크기 경계를 검증한다.
 *
 * <p>파일 Byte 크기 제한과 별개로 압축 해제 후 과도한 메모리를 점유하는 이미지와 분석 좌표 기준으로 사용할 수 없는 지나치게 작은 이미지를 저장 전에 차단한다.
 */
final class ImageDimensionPolicy {

  static final int MIN_DIMENSION_PX = 320;
  static final int MAX_DIMENSION_PX = 8192;

  private ImageDimensionPolicy() {}

  /**
   * 이미지의 가로와 세로가 모두 허용 범위인지 검증한다.
   *
   * @param widthPx 이미지 가로 픽셀 수
   * @param heightPx 이미지 세로 픽셀 수
   * @throws BusinessException 어느 한 변이라도 {@value #MIN_DIMENSION_PX} 미만이거나 {@value #MAX_DIMENSION_PX}
   *     초과인 경우
   */
  static void validate(int widthPx, int heightPx) {
    if (widthPx < MIN_DIMENSION_PX
        || heightPx < MIN_DIMENSION_PX
        || widthPx > MAX_DIMENSION_PX
        || heightPx > MAX_DIMENSION_PX) {
      throw new BusinessException(ImageStorageErrorCode.IMAGE_DIMENSION_INVALID);
    }
  }
}
