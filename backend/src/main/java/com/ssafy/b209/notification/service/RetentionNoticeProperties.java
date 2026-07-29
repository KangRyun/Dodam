package com.ssafy.b209.notification.service;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 보관 만료 임박 알림 주기 작업의 실행 여부와 기준일을 관리한다.
 *
 * <p>데이터 보관 정책(S15P11B209-564·565)이 확정되기 전이라 실제 보관·삭제예정 컬럼이 스키마에 없다. 그래서 기준일을 코드에 박지 않고 이 프로퍼티로 빼며,
 * {@link #enabled}는 기본 {@code false}로 두어 가짜 정책으로 알림이 오발송되지 않게 게이트한다. 보관 정책이 확정되면 그 도메인이 실제 만료 시각과
 * 재알림 억제를 소유하고, 여기 기준일은 임시값이다(557 as-built §보관 만료 기준).
 */
@Component
@ConfigurationProperties(prefix = "app.notification.retention")
public class RetentionNoticeProperties {

  private boolean enabled = false;
  private int retentionDays = 180;
  private int noticeDaysBefore = 30;
  private int batchSize = 100;

  /**
   * @return 보관 만료 임박 알림 발송을 실제로 수행하는지 여부이며 기본은 {@code false}
   */
  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  /**
   * @return 데이터를 보관하는 기간(일). 보관 정책 확정 전 임시 기준값이다
   */
  public int getRetentionDays() {
    return retentionDays;
  }

  public void setRetentionDays(int retentionDays) {
    this.retentionDays = retentionDays;
  }

  /**
   * @return 보관 만료 며칠 전에 안내할지(일)
   */
  public int getNoticeDaysBefore() {
    return noticeDaysBefore;
  }

  public void setNoticeDaysBefore(int noticeDaysBefore) {
    this.noticeDaysBefore = noticeDaysBefore;
  }

  /**
   * @return 한 번의 실행에서 처리할 최대 대상 수
   */
  public int getBatchSize() {
    return batchSize;
  }

  public void setBatchSize(int batchSize) {
    this.batchSize = batchSize;
  }
}
