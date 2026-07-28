package com.ssafy.b209.storage.audio;

import java.time.Clock;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

/** 음성 전용 로컬 저장 구현체를 Spring Bean으로 등록한다. */
@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(
    prefix = "app.storage",
    name = "mode",
    havingValue = "local",
    matchIfMissing = true)
@EnableConfigurationProperties(AudioStorageProperties.class)
public class AudioStorageConfig {

  /** Spring 설정 인스턴스를 생성한다. */
  public AudioStorageConfig() {}

  /**
   * 이미지 Root와 분리된 음성 저장소를 제공한다.
   *
   * @param properties 음성 저장 경로·크기 정책
   * @param clock 날짜 기반 상대 key 생성 시계
   * @return 음성 업로드 전용 Storage
   */
  @Bean
  @Primary
  public AudioStorage audioStorage(AudioStorageProperties properties, Clock clock) {
    return new LocalAudioStorage(properties, clock);
  }

  /**
   * 로컬 모드에서는 TTS도 같은 보호된 음성 Root를 사용하되 용도별 Bean 계약을 유지한다.
   *
   * @param audioStorage 로컬 음성 저장소
   * @return TTS 생성·재생에 사용할 동일한 로컬 저장소
   */
  @Bean("ttsAudioStorage")
  public AudioStorage ttsAudioStorage(@Qualifier("audioStorage") AudioStorage audioStorage) {
    return audioStorage;
  }
}
