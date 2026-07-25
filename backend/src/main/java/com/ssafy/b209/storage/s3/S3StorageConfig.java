package com.ssafy.b209.storage.s3;

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
@EnableConfigurationProperties(S3StorageProperties.class)
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
}
