package com.ssafy.b209.global.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class TimeConfigTest {

  private final ApplicationContextRunner contextRunner =
      new ApplicationContextRunner().withUserConfiguration(TimeConfig.class);

  @Test
  void providesUtcClockBean() {
    contextRunner.run(
        context -> assertThat(context.getBean(Clock.class).getZone()).isEqualTo(ZoneOffset.UTC));
  }
}
