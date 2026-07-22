package com.ssafy.b209.storage.image;

import java.time.Clock;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** 로컬 이미지 저장 설정을 Spring Application Context에 등록하는 구성이다. */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(ImageStorageProperties.class)
public class ImageStorageConfig {

  /** Spring이 이미지 저장 설정을 구성할 때 사용하는 기본 생성자다. */
  public ImageStorageConfig() {}

  /**
   * 로컬 파일 시스템을 사용하는 이미지 저장 구현체를 제공한다.
   *
   * @param properties 환경별 이미지 저장 설정
   * @param clock 날짜별 Storage Key를 생성하는 UTC 기준 시계
   * @return 후속 그림 업로드 Service가 사용할 이미지 저장 경계
   */
  @Bean
  public ImageStorage imageStorage(ImageStorageProperties properties, Clock clock) {
    return new LocalImageStorage(properties, clock);
  }
}
