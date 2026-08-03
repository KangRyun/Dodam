package com.ssafy.b209.storage.credential;

import java.nio.file.Path;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * 전문가 자격 증빙 전용 로컬 Root와 크기 제한이다.
 *
 * @param root 다른 파일 종류와 분리된 저장 Root
 * @param maxSize 허용할 실제 파일 Byte 상한
 */
@ConfigurationProperties(prefix = "app.storage.credential")
public record CredentialFileStorageProperties(
    @DefaultValue("./storage/credentials") Path root, @DefaultValue("10485760") long maxSize) {

  /** 설정을 정규화하고 10MiB 이하의 양수 제한인지 확인한다. */
  public CredentialFileStorageProperties {
    if (root == null || root.toString().isBlank() || maxSize <= 0 || maxSize > 10_485_760L) {
      throw new IllegalArgumentException("Credential storage properties are invalid");
    }
    root = root.toAbsolutePath().normalize();
  }
}
