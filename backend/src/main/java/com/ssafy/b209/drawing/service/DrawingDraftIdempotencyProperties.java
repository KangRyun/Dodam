package com.ssafy.b209.drawing.service;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/** Draft 저장 멱등성 레코드의 처리·완료 TTL과 처리 중 대기 시간을 관리한다. */
@Component
@ConfigurationProperties(prefix = "app.idempotency.drawing-draft")
public class DrawingDraftIdempotencyProperties {

  private Duration processingTtl = Duration.ofSeconds(30);
  private Duration completedTtl = Duration.ofHours(24);
  private Duration processingWait = Duration.ofSeconds(3);
  private Duration pollingInterval = Duration.ofMillis(50);

  public Duration getProcessingTtl() {
    return processingTtl;
  }

  public void setProcessingTtl(Duration processingTtl) {
    this.processingTtl = processingTtl;
  }

  public Duration getCompletedTtl() {
    return completedTtl;
  }

  public void setCompletedTtl(Duration completedTtl) {
    this.completedTtl = completedTtl;
  }

  public Duration getProcessingWait() {
    return processingWait;
  }

  public void setProcessingWait(Duration processingWait) {
    this.processingWait = processingWait;
  }

  public Duration getPollingInterval() {
    return pollingInterval;
  }

  public void setPollingInterval(Duration pollingInterval) {
    this.pollingInterval = pollingInterval;
  }
}
