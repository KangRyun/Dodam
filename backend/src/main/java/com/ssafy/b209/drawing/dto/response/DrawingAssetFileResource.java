package com.ssafy.b209.drawing.dto.response;

import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.IOException;
import java.util.Objects;

/**
 * 권한 검증을 마친 그림 파일 Stream과 전송 Metadata를 Controller에 전달한다.
 *
 * <p>호출자는 응답 전송이 끝나면 반드시 {@link #close()}를 호출해야 한다. Storage Key나 서버 파일 경로는 포함하지 않는다.
 *
 * @param content Storage에서 연 그림 파일과 전송 Metadata
 */
public record DrawingAssetFileResource(StoredImageContent content) implements AutoCloseable {

  /** 그림 파일 조회 결과의 필수 Stream을 검증한다. */
  public DrawingAssetFileResource {
    Objects.requireNonNull(content, "content");
  }

  /**
   * 보유한 그림 파일 Stream을 닫는다.
   *
   * @throws IOException Stream을 닫는 과정에서 입출력 오류가 발생한 경우
   */
  @Override
  public void close() throws IOException {
    content.close();
  }
}
