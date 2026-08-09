package com.ssafy.b209.conversation.service;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/** 이벤트 유실로 PENDING에 정체된 음성 답변을 회수하는 주기 작업의 대상 선정 조건을 관리한다. */
@Component
@ConfigurationProperties(prefix = "app.stt.recovery")
public class SttRecoveryProperties {
  private Duration minimumAge = Duration.ofMinutes(2);
  private int batchSize = 20;

  /**
   * @return 정체로 판단하기까지 기다리는 최소 경과 시간. 정상 진행 중인 STT를 회수 대상으로 삼지 않기 위한 여유다
   */
  public Duration getMinimumAge() {
    return minimumAge;
  }

  public void setMinimumAge(Duration minimumAge) {
    this.minimumAge = minimumAge;
  }

  /**
   * @return 한 번의 실행에서 처리할 최대 메시지 수
   */
  public int getBatchSize() {
    return batchSize;
  }

  public void setBatchSize(int batchSize) {
    this.batchSize = batchSize;
  }
}
