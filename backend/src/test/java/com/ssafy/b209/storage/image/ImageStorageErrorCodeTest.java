package com.ssafy.b209.storage.image;

import static org.assertj.core.api.Assertions.assertThat;

import com.ssafy.b209.global.response.ErrorCode;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class ImageStorageErrorCodeTest {

  @Test
  void exposesTheExactImageStorageErrorCodeContract() {
    Map<ImageStorageErrorCode, ErrorContract> expected =
        Map.of(
            ImageStorageErrorCode.EMPTY_IMAGE_FILE,
                new ErrorContract(
                    HttpStatus.BAD_REQUEST, "STORAGE_400_001", "저장할 이미지 파일이 비어 있습니다."),
            ImageStorageErrorCode.UNSUPPORTED_IMAGE_FORMAT,
                new ErrorContract(HttpStatus.BAD_REQUEST, "STORAGE_400_002", "지원하지 않는 이미지 형식입니다."),
            ImageStorageErrorCode.INVALID_IMAGE_FILE,
                new ErrorContract(HttpStatus.BAD_REQUEST, "STORAGE_400_003", "유효한 이미지 파일이 아닙니다."),
            ImageStorageErrorCode.INVALID_STORAGE_PATH,
                new ErrorContract(
                    HttpStatus.BAD_REQUEST, "STORAGE_400_004", "유효하지 않은 이미지 저장 경로입니다."),
            ImageStorageErrorCode.IMAGE_STORAGE_CONFLICT,
                new ErrorContract(HttpStatus.CONFLICT, "STORAGE_409_001", "이미지 저장 요청이 충돌했습니다."),
            ImageStorageErrorCode.IMAGE_NOT_FOUND,
                new ErrorContract(HttpStatus.NOT_FOUND, "STORAGE_404_001", "이미지 파일을 찾을 수 없습니다."),
            ImageStorageErrorCode.IMAGE_FILE_TOO_LARGE,
                new ErrorContract(
                    HttpStatus.PAYLOAD_TOO_LARGE, "STORAGE_413_001", "이미지 파일 크기가 허용 범위를 초과했습니다."),
            ImageStorageErrorCode.IMAGE_STORAGE_FAILED,
                new ErrorContract(
                    HttpStatus.INTERNAL_SERVER_ERROR, "STORAGE_500_001", "이미지 저장 중 오류가 발생했습니다."));

    assertThat(ImageStorageErrorCode.values())
        .containsExactlyInAnyOrderElementsOf(expected.keySet());
    expected.forEach(ImageStorageErrorCodeTest::assertContract);
  }

  private static void assertContract(ImageStorageErrorCode errorCode, ErrorContract expected) {
    assertThat(errorCode).isInstanceOf(ErrorCode.class);
    assertThat(errorCode.getHttpStatus()).isEqualTo(expected.httpStatus());
    assertThat(errorCode.getCode()).isEqualTo(expected.code());
    assertThat(errorCode.getMessage()).isEqualTo(expected.message());
  }

  private record ErrorContract(HttpStatus httpStatus, String code, String message) {}
}
