package com.ssafy.b209.storage.s3;

import java.net.URI;
import java.util.Locale;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * S3 호환 Object Storage 연결과 파일 종류별 Prefix 설정을 제공한다.
 *
 * <p>자격증명은 환경 변수로 주입하며 로그나 오류 메시지에 포함하지 않는다.
 *
 * @param endpoint S3 API Endpoint
 * @param region S3 서명에 사용하는 Region
 * @param bucket 그림과 음성을 저장할 Bucket
 * @param accessKey Backend 전용 Access Key
 * @param secretKey Backend 전용 Secret Key
 * @param imagePrefix 그림 객체 Prefix
 * @param audioPrefix 아동 음성 원본 객체 Prefix
 * @param ttsPrefix 재생성 가능한 TTS 캐시 객체 Prefix
 * @param credentialPrefix 전문가 자격 증빙 객체 Prefix
 * @param pathStyleAccessEnabled MinIO 호환 Path-style 접근 사용 여부
 */
@ConfigurationProperties(prefix = "app.storage.s3")
public record S3StorageProperties(
    @DefaultValue("http://localhost:9000") URI endpoint,
    @DefaultValue("ap-northeast-2") String region,
    @DefaultValue("dodam") String bucket,
    String accessKey,
    String secretKey,
    @DefaultValue("images") String imagePrefix,
    @DefaultValue("audio") String audioPrefix,
    @DefaultValue("tts-cache") String ttsPrefix,
    @DefaultValue("credentials") String credentialPrefix,
    @DefaultValue("true") boolean pathStyleAccessEnabled) {

  /** S3 Client가 안전하게 사용할 수 있도록 설정값을 검증하고 Prefix를 정규화한다. */
  public S3StorageProperties {
    if (endpoint == null
        || endpoint.getScheme() == null
        || endpoint.getHost() == null
        || !("http".equals(endpoint.getScheme().toLowerCase(Locale.ROOT))
            || "https".equals(endpoint.getScheme().toLowerCase(Locale.ROOT)))) {
      throw new IllegalArgumentException("S3 endpoint must be an HTTP(S) URI");
    }
    requireText(region, "S3 region");
    requireText(bucket, "S3 bucket");
    requireText(accessKey, "S3 access key");
    requireText(secretKey, "S3 secret key");
    imagePrefix = normalizePrefix(imagePrefix, "S3 image prefix");
    audioPrefix = normalizePrefix(audioPrefix, "S3 audio prefix");
    ttsPrefix = normalizePrefix(ttsPrefix, "S3 TTS prefix");
    credentialPrefix = normalizePrefix(credentialPrefix, "S3 credential prefix");
  }

  private static void requireText(String value, String name) {
    if (value == null || value.isBlank()) {
      throw new IllegalArgumentException(name + " must not be blank");
    }
  }

  private static String normalizePrefix(String value, String name) {
    requireText(value, name);
    String normalized = value.trim();
    while (normalized.startsWith("/")) {
      normalized = normalized.substring(1);
    }
    while (normalized.endsWith("/")) {
      normalized = normalized.substring(0, normalized.length() - 1);
    }
    if (normalized.isBlank()
        || normalized.contains("\\")
        || normalized.contains("..")
        || normalized.contains("//")) {
      throw new IllegalArgumentException(name + " is invalid");
    }
    return normalized;
  }
}
