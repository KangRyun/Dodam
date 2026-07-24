package com.ssafy.b209.storage.image;

import java.io.IOException;
import java.io.InputStream;
import java.util.Objects;

/**
 * Storage에서 조회한 이미지 Stream과 전송에 필요한 Metadata를 함께 전달한다.
 *
 * <p>호출자는 사용을 마치면 반드시 {@link #close()}를 호출해야 한다. 파일 시스템 경로와 Storage Key는 외부 응답에 노출되지 않도록 이 객체에 포함하지
 * 않는다.
 *
 * @param inputStream 이미지 내용을 읽는 Stream
 * @param contentType 검증된 이미지 MIME Type
 * @param size 이미지 크기(Byte)
 */
public record StoredImageContent(InputStream inputStream, String contentType, long size)
    implements AutoCloseable {

  /** 조회 결과의 필수 값과 크기를 검증한다. */
  public StoredImageContent {
    Objects.requireNonNull(inputStream, "inputStream must not be null");
    if (contentType == null || contentType.isBlank()) {
      throw new IllegalArgumentException("contentType must not be blank");
    }
    if (size <= 0) {
      throw new IllegalArgumentException("size must be positive");
    }
  }

  /** 보유한 이미지 Stream을 닫는다. */
  @Override
  public void close() throws IOException {
    inputStream.close();
  }

  /**
   * 민감한 파일 경로나 Stream 구현 정보 없이 전송 Metadata만 표현한다.
   *
   * @return Content-Type과 이미지 크기를 포함한 문자열
   */
  @Override
  public String toString() {
    return "StoredImageContent[contentType=" + contentType + ", size=" + size + "]";
  }
}
