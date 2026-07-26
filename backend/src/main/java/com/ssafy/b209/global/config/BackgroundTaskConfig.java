package com.ssafy.b209.global.config;

import java.util.concurrent.ThreadPoolExecutor;
import org.springframework.boot.autoconfigure.task.TaskExecutionAutoConfiguration;
import org.springframework.boot.task.ThreadPoolTaskExecutorBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/**
 * HTTP 응답과 분리해 실행하는 백그라운드 작업의 실행기와 주기 실행을 구성한다.
 *
 * <p>STT 처리는 요청 Thread를 점유하면 업로드 응답이 외부 AI 소요 시간만큼 지연되므로 전용 Pool에서 실행한다. Pool을 분리하지 않으면 최대 30초짜리
 * STT 호출이 MVC async 응답(음성 프록시 스트리밍)과 같은 Pool을 잡아 재생이 밀린다.
 *
 * <p>Spring Boot의 {@code applicationTaskExecutor} 자동 구성은 {@code Executor} 빈이 하나라도 있으면 물러난다. 전용
 * Pool을 추가하면 MVC async 실행기가 사라져 요청마다 Thread를 새로 만드는 기본 동작으로 후퇴하므로, Boot와 같은 설정({@code
 * spring.task.execution.*})을 쓰는 실행기를 같은 이름으로 다시 등록한다.
 */
@Configuration
@EnableAsync
@EnableScheduling
public class BackgroundTaskConfig {

  /** Spring 컨테이너가 구성 클래스를 생성할 때 사용하는 생성자다. */
  public BackgroundTaskConfig() {}

  /**
   * Boot 자동 구성이 물러난 자리를 대신해 공용 비동기 실행기를 등록한다.
   *
   * <p>MVC async 처리와 한정자 없는 {@code @Async}가 이 실행기를 사용한다.
   *
   * @param builder {@code spring.task.execution.*} 설정이 적용된 Boot 기본 builder
   * @return Boot 기본값과 동일한 공용 실행기
   */
  @Bean(name = TaskExecutionAutoConfiguration.APPLICATION_TASK_EXECUTOR_BEAN_NAME)
  public ThreadPoolTaskExecutor applicationTaskExecutor(ThreadPoolTaskExecutorBuilder builder) {
    return builder.build();
  }

  /**
   * 음성 답변 STT 처리 전용 Thread Pool을 만든다.
   *
   * <p>Queue를 유한하게 두어 폭주 시 호출 Thread가 대신 실행하도록 하고, 종료 시 진행 중 작업을 기다려 PENDING 정체를 줄인다.
   *
   * @return STT 이벤트 소비에 사용하는 실행기
   */
  @Bean
  public ThreadPoolTaskExecutor sttTaskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(2);
    executor.setMaxPoolSize(4);
    executor.setQueueCapacity(100);
    executor.setThreadNamePrefix("stt-");
    executor.setWaitForTasksToCompleteOnShutdown(true);
    executor.setAwaitTerminationSeconds(30);
    executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
    return executor;
  }
}
