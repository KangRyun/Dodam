package com.ssafy.b209.storage.audio;

import java.io.IOException;
import java.io.InputStream;
import java.util.Objects;

/**
 * Storage에서 조회한 음성 Stream과 HTTP 전송에 필요한 Metadata를 함께 전달한다.
 *
 * <p>호출자는 사용을 마치면 반드시 {@link #close()}를 호출해야 한다. 내부 Storage Key나 파일 시스템 경로는 포함하지 않는다.
 *
 * @param inputStream 음성 내용을 읽는 Stream
 * @param contentType 검증된 음성 MIME Type
 * @param size 음성 파일 크기(Byte)
 */
public record StoredAudioContent(InputStream inputStream, String contentType, long size)
    implements AutoCloseable {

  /** 조회 결과가 유효한 Stream과 전송 Metadata를 갖는지 검증한다. */
  public StoredAudioContent {
    Objects.requireNonNull(inputStream, "inputStream must not be null");
    if (contentType == null || contentType.isBlank()) {
      throw new IllegalArgumentException("contentType must not be blank");
    }
    if (size <= 0) {
      throw new IllegalArgumentException("size must be positive");
    }
  }

  /** 보유한 음성 Stream을 닫는다. */
  @Override
  public void close() throws IOException {
    inputStream.close();
  }

  /**
   * 파일 경로나 Stream 구현 정보 없이 전송 Metadata만 표현한다.
   *
   * @return Content-Type과 음성 크기를 포함한 문자열
   */
  @Override
  public String toString() {
    return "StoredAudioContent[contentType=" + contentType + ", size=" + size + "]";
  }
}
