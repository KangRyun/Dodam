package com.ssafy.b209.storage.audio;

import java.nio.file.Path;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * 음성 전용 로컬 저장 Root와 최대 파일 크기 설정이다.
 *
 * @param root 음성 파일만 보관하는 정규화 절대 Root
 * @param maxSize 한 요청에서 허용할 실제 음성 Byte 상한
 */
@ConfigurationProperties(prefix = "app.storage.audio")
public record AudioStorageProperties(
    @DefaultValue("./storage/audio") Path root, @DefaultValue("20971520") long maxSize) {

  /** 설정값을 파일 시스템 구현이 안전하게 쓸 수 있게 검증·정규화한다. */
  public AudioStorageProperties {
    if (root == null || root.toString().isBlank() || maxSize <= 0) {
      throw new IllegalArgumentException("Audio storage properties are invalid");
    }
    root = root.toAbsolutePath().normalize();
  }
}
