package com.ssafy.b209.child.dto.response;

import com.ssafy.b209.storage.image.StoredImageContent;
import java.io.IOException;
import java.util.Objects;

/**
 * 접근 권한을 확인한 아동 프로필 이미지 Stream을 Controller에 전달한다.
 *
 * @param content Storage에서 연 이미지와 전송 Metadata
 */
public record ChildProfileImageFileResource(StoredImageContent content) implements AutoCloseable {

  public ChildProfileImageFileResource {
    Objects.requireNonNull(content);
  }

  @Override
  public void close() throws IOException {
    content.close();
  }
}
