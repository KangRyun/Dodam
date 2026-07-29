package com.ssafy.b209.storage.s3;

import com.ssafy.b209.storage.audio.AudioStorage;
import com.ssafy.b209.storage.audio.AudioStorageProperties;
import com.ssafy.b209.storage.audio.LocalAudioStorage;
import com.ssafy.b209.storage.audio.StorageDelegatingStoredAudioReader;
import com.ssafy.b209.storage.audio.StoredAudioReader;
import com.ssafy.b209.storage.image.ImageStorage;
import com.ssafy.b209.storage.image.ImageStorageProperties;
import com.ssafy.b209.storage.image.LocalImageStorage;
import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
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
  @Primary
  public AudioStorage audioStorage(
      S3Client s3Client,
      S3StorageProperties s3Properties,
      AudioStorageProperties audioProperties,
      Clock clock) {
    return new S3AudioStorage(
        s3Client, s3Properties, new LocalAudioStorage(audioProperties, clock));
  }

  /**
   * 30일 만료 정책이 적용되는 Prefix에 AI 질문 TTS 캐시를 저장한다.
   *
   * @param s3Client S3 호환 API Client
   * @param s3Properties Bucket과 TTS 캐시 Prefix 설정
   * @param audioProperties Local staging 경로와 음성 크기 제한
   * @param clock 날짜 기반 Storage Key 생성용 UTC 시계
   * @return TTS 생성·재생 전용 Storage
   */
  @Bean("ttsAudioStorage")
  public AudioStorage ttsAudioStorage(
      S3Client s3Client,
      S3StorageProperties s3Properties,
      AudioStorageProperties audioProperties,
      Clock clock) {
    return new S3AudioStorage(
        s3Client,
        s3Properties,
        s3Properties.ttsPrefix(),
        new LocalAudioStorage(audioProperties, clock));
  }

  /**
   * 내부 STT 요청이 S3에 보관된 아동 음성을 읽도록 Reader를 등록한다(S15P11B209-723).
   *
   * <p>이 빈이 없으면 s3 모드에서도 {@code LocalStoredAudioReader}가 등록돼 로컬 Root를 뒤진다. 파일은 MinIO에 있으므로 업로드는
   * 201로 성공하는데 STT만 {@code STT_AUDIO_NOT_AVAILABLE}로 전부 실패한다(2026-07-29 운영 실측 — AI 서버에 STT 요청이 0건
   * 도달).
   *
   * <p>TTS 캐시가 아니라 아동 음성 답변을 읽어야 하므로 {@link Primary} 음성 Storage를 주입받는다.
   *
   * @param audioStorage s3 모드의 기본 음성 Storage(아동 음성 프리픽스)
   * @return 저장에 쓴 경계로 읽는 Reader
   */
  @Bean
  public StoredAudioReader storedAudioReader(AudioStorage audioStorage) {
    return new StorageDelegatingStoredAudioReader(audioStorage);
  }
}
