package com.ssafy.b209.storage.credential;

import java.time.Clock;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** 로컬 모드의 전문가 자격 증빙 Storage를 등록한다. */
@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(
    prefix = "app.storage",
    name = "mode",
    havingValue = "local",
    matchIfMissing = true)
@EnableConfigurationProperties(CredentialFileStorageProperties.class)
public class CredentialFileStorageConfig {

  /** Spring 설정 인스턴스를 생성한다. */
  public CredentialFileStorageConfig() {}

  /**
   * @param properties 자격 증빙 Root와 최대 크기
   * @param clock 날짜 기반 Key 생성 시계
   * @return 자격 증빙 전용 로컬 Storage
   */
  @Bean
  public CredentialFileStorage credentialFileStorage(
      CredentialFileStorageProperties properties, Clock clock) {
    return new LocalCredentialFileStorage(properties, clock);
  }
}
