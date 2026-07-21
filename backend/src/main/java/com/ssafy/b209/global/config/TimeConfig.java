package com.ssafy.b209.global.config;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** 애플리케이션이 시간 계산에 일관된 UTC 기준 시계를 사용하도록 구성한다. */
@Configuration
public class TimeConfig {

  /** Spring이 시간 설정을 생성할 때 사용하는 기본 생성자다. */
  public TimeConfig() {}

  /**
   * 시간 의존 도메인과 서비스에 UTC 기준 시계를 제공한다.
   *
   * @return 시스템 UTC 시계
   */
  @Bean
  public Clock clock() {
    return Clock.systemUTC();
  }
}
