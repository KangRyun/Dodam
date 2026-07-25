package com.ssafy.b209.storage.s3;

import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.AudioStorageProperties;
import com.ssafy.b209.storage.audio.LocalAudioStorage;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.ImageStorageProperties;
import com.ssafy.b209.storage.image.LocalImageStorage;
import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;

/** S3 모드에서 MinIO 호환 Client와 Storage Adapter 기반 설정을 등록한다. */
@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(prefix = "app.storage", name = "mode", havingValue = "s3")
@EnableConfigurationProperties({
  S3StorageProperties.class,
  ImageStorageProperties.class,
  AudioStorageProperties.class
})
public class S3StorageConfig {

  /** Spring이 S3 모드 설정을 생성할 때 사용하는 기본 생성자다. */
  public S3StorageConfig() {}

  /**
   * Backend 전용 정적 자격증명과 Path-style 접근을 사용하는 S3 Client를 생성한다.
   *
   * @param properties S3 Endpoint와 Backend 전용 자격증명
   * @return 애플리케이션 종료 시 함께 닫히는 S3 Client
   */
  @Bean(destroyMethod = "close")
  public S3Client s3Client(S3StorageProperties properties) {
    return S3Client.builder()
        .endpointOverride(properties.endpoint())
        .region(Region.of(properties.region()))
        .credentialsProvider(
            StaticCredentialsProvider.create(
                AwsBasicCredentials.create(properties.accessKey(), properties.secretKey())))
        .serviceConfiguration(
            S3Configuration.builder()
                .pathStyleAccessEnabled(properties.pathStyleAccessEnabled())
                .build())
        .httpClientBuilder(UrlConnectionHttpClient.builder())
        .build();
  }

  /**
   * 기존 검증 규칙을 staging으로 재사용하는 S3 이미지 저장소를 생성한다.
   *
   * @param s3Client S3 호환 API Client
   * @param s3Properties Bucket과 Prefix 설정
   * @param imageProperties Local staging 경로와 이미지 크기 제한
   * @param clock 날짜 기반 Storage Key 생성용 UTC 시계
   * @return S3 모드에서 사용할 이미지 Storage
   */
  @Bean
  public ImageStorage imageStorage(
      S3Client s3Client,
      S3StorageProperties s3Properties,
      ImageStorageProperties imageProperties,
      Clock clock) {
    return new S3ImageStorage(
        s3Client, s3Properties, new LocalImageStorage(imageProperties, clock));
  }

  /**
   * 기존 검증·staging 흐름을 재사용하는 S3 음성 저장소를 생성한다.
   *
   * @param s3Client S3 호환 API Client
   * @param s3Properties Bucket과 Prefix 설정
   * @param audioProperties Local staging 경로와 음성 크기 제한
   * @param clock 날짜 기반 Storage Key 생성용 UTC 시계
   * @return S3 모드에서 사용할 음성 Storage
   */
  @Bean
  public AudioStorage audioStorage(
      S3Client s3Client,
      S3StorageProperties s3Properties,
      AudioStorageProperties audioProperties,
      Clock clock) {
    return new S3AudioStorage(
        s3Client, s3Properties, new LocalAudioStorage(audioProperties, clock));
  }
}
