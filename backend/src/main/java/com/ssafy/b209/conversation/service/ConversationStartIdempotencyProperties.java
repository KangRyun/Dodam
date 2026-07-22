package com.ssafy.b209.conversation.service;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/** 대화 시작 Redis 멱등성 레코드의 만료와 처리 중 대기 시간을 관리한다. */
@Component
@ConfigurationProperties(prefix = "app.idempotency.conversation")
public class ConversationStartIdempotencyProperties {
  private Duration processingTtl = Duration.ofSeconds(30);
  private Duration completedTtl = Duration.ofHours(24);
  private Duration failureTtl = Duration.ofMinutes(5);
  private Duration processingWait = Duration.ofSeconds(3);
  private Duration pollingInterval = Duration.ofMillis(50);

  /**
   * @return 최초 요청이 완료되기를 기다리는 Redis PROCESSING 상태의 만료 시간
   */
  public Duration getProcessingTtl() {
    return processingTtl;
  }

  public void setProcessingTtl(Duration processingTtl) {
    this.processingTtl = processingTtl;
  }

  /**
   * @return 성공 또는 업무 오류의 최초 HTTP 응답을 재생하는 보존 시간
   */
  public Duration getCompletedTtl() {
    return completedTtl;
  }

  public void setCompletedTtl(Duration completedTtl) {
    this.completedTtl = completedTtl;
  }

  /**
   * @return 예상하지 못한 5xx 응답을 짧게 재생하는 보존 시간
   */
  public Duration getFailureTtl() {
    return failureTtl;
  }

  public void setFailureTtl(Duration failureTtl) {
    this.failureTtl = failureTtl;
  }

  /**
   * @return 동일 키의 처리 중 요청을 폴링하는 최대 시간
   */
  public Duration getProcessingWait() {
    return processingWait;
  }

  public void setProcessingWait(Duration processingWait) {
    this.processingWait = processingWait;
  }

  /**
   * @return 처리 중 상태를 다시 조회하는 간격
   */
  public Duration getPollingInterval() {
    return pollingInterval;
  }

  public void setPollingInterval(Duration pollingInterval) {
    this.pollingInterval = pollingInterval;
  }
}
