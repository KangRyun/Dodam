package com.ssafy.b209.storage.image;

import java.nio.file.Path;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * 로컬 이미지 Storage Root와 파일별 최대 허용 크기를 제공하는 설정이다.
 *
 * <p>Root는 현재 실행 디렉터리를 기준으로 절대·정규화한다. 환경별 설정은 {@code app.storage.image} 또는 대응하는 환경 변수로 제공한다.
 *
 * @param root 이미지 파일을 보관할 정규화된 절대 Root 경로
 * @param maxSize 이미지 한 건의 최대 허용 크기(Byte)
 */
@ConfigurationProperties(prefix = "app.storage.image")
public record ImageStorageProperties(
    @DefaultValue("./storage/images") Path root, @DefaultValue("10485760") long maxSize) {

  /**
   * 설정값을 저장 구현체가 안전하게 사용할 수 있는 형태로 검증하고 정규화한다.
   *
   * @throws IllegalArgumentException Root가 비어 있거나 최대 허용 크기가 양수가 아닌 경우
   */
  public ImageStorageProperties {
    if (root == null || root.toString().isBlank()) {
      throw new IllegalArgumentException("Image storage root must not be blank");
    }
    if (maxSize <= 0) {
      throw new IllegalArgumentException("Image storage max size must be positive");
    }
    root = root.toAbsolutePath().normalize();
  }
}
