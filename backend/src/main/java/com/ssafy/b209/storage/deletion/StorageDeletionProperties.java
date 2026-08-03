package com.ssafy.b209.storage.deletion;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/** {@code storage_deletion_jobs} 소비 워커의 실행 조건을 관리한다 (S15P11B209-780). */
@Component
@ConfigurationProperties(prefix = "app.storage.deletion")
public class StorageDeletionProperties {

  private boolean enabled = true;
  private Duration interval = Duration.ofSeconds(60);
  private int batchSize = 100;
  private int maxRetryCount = 5;
  private Duration stuckAfter = Duration.ofMinutes(10);

  /**
   * @return 워커 실행 여부. 끄면 잡이 쌓이기만 하므로 점검 창에서만 잠시 끈다
   */
  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  /**
   * @return 실행 간격. 삭제는 사용자 응답 경로가 아니라 지연에 관대하다
   */
  public Duration getInterval() {
    return interval;
  }

  public void setInterval(Duration interval) {
    this.interval = interval;
  }

  /**
   * @return 한 번의 실행에서 처리할 최대 잡 수. 아동 삭제 한 건이 수백 개의 잡을 만들 수 있어 배치로 나눈다
   */
  public int getBatchSize() {
    return batchSize;
  }

  public void setBatchSize(int batchSize) {
    this.batchSize = batchSize;
  }

  /**
   * @return 이 횟수를 넘기면 FAILED 로 두고 더 시도하지 않는다. 사람이 봐야 하는 상태이므로 무한 재시도로 감추지 않는다
   */
  public int getMaxRetryCount() {
    return maxRetryCount;
  }

  public void setMaxRetryCount(int maxRetryCount) {
    this.maxRetryCount = maxRetryCount;
  }

  /**
   * @return PROCESSING 으로 선점된 뒤 이 시간이 지나면 죽은 파드가 물고 있던 것으로 보고 회수한다.
   *     회수가 없으면 파드가 배포·OOM 으로 죽을 때마다 잡이 영구히 PROCESSING 에 갇힌다
   */
  public Duration getStuckAfter() {
    return stuckAfter;
  }

  public void setStuckAfter(Duration stuckAfter) {
    this.stuckAfter = stuckAfter;
  }
}
