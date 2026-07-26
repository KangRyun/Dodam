package com.ssafy.b209.global.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.task.TaskExecutionAutoConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import org.springframework.test.context.ActiveProfiles;

/**
 * 백그라운드 실행기 구성이 MVC async 실행기를 빼앗지 않는지 검증한다.
 *
 * <p>전용 STT Pool을 추가하면 Boot의 {@code applicationTaskExecutor} 자동 구성이 물러난다. 그 자리를 직접 채우지 않으면 음성 프록시
 * 스트리밍이 요청마다 Thread를 새로 만드는 기본 동작으로 조용히 후퇴한다.
 */
@SpringBootTest
@ActiveProfiles("test")
class BackgroundTaskConfigTest {

  @Autowired private ApplicationContext applicationContext;

  @Autowired
  @Qualifier("sttTaskExecutor")
  private ThreadPoolTaskExecutor sttTaskExecutor;

  @Test
  void keepsSharedApplicationTaskExecutorAvailable() {
    assertThat(
            applicationContext.containsBean(
                TaskExecutionAutoConfiguration.APPLICATION_TASK_EXECUTOR_BEAN_NAME))
        .isTrue();
  }

  @Test
  void isolatesSttProcessingOnItsOwnBoundedPool() {
    assertThat(sttTaskExecutor.getThreadNamePrefix()).isEqualTo("stt-");
    assertThat(sttTaskExecutor.getMaxPoolSize()).isEqualTo(4);
    assertThat(sttTaskExecutor)
        .isNotSameAs(
            applicationContext.getBean(
                TaskExecutionAutoConfiguration.APPLICATION_TASK_EXECUTOR_BEAN_NAME));
  }
}
