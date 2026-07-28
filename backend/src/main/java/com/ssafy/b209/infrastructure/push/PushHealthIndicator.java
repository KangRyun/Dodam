package com.ssafy.b209.infrastructure.push;

import com.ssafy.b209.notification.push.PushSender;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * 푸시 발송의 실제 가용 상태를 알린다 — "설정상 켜짐"과 "실제 발송 가능"을 구분해서 드러내는 것이 목적이다.
 *
 * <p>이 지표가 필요한 이유는 S15P11B209-681 이다. 설정은 켜져 있는데 자격증명을 쓸 수 없어 실제로는 발송되지 않는 상태가 조용히 유지되면, 보호자는 분석 완료
 * 알림을 받지 못하는데 아무도 모른다.
 *
 * <h2>왜 {@code DOWN}을 반환하지 않는가</h2>
 *
 * 푸시는 부가 기능이다. 여기서 {@code DOWN}을 내면 애플리케이션 전체 health 가 내려가고, 그것은 컨테이너 헬스체크 실패 → 게이트웨이 기동 차단 → 서비스 전면
 * 중단으로 이어진다. 2026-07-28 장애가 정확히 그 연쇄였다. 부가 기능의 문제를 핵심 가용성 신호에 섞지 않는다.
 *
 * <h2>그러면 어떻게 알아채는가</h2>
 *
 * {@code app.push.fcm} 설정은 {@code show-details: never}(아동 서비스 가드레일)라 health 상세가 외부로 나가지 않는다. 그래서 실질
 * 관측 수단은 Micrometer 게이지 {@code dodam.push.sending.enabled} 다. 내부망 전용 관리 포트(9404)의 Prometheus 스크레이프로
 * 수집되며, {@code configured="true"} 인데 값이 {@code 0} 이면 "켜려 했으나 발송 불가" 상태다.
 */
@Component
public class PushHealthIndicator implements HealthIndicator {

  /** 게이지 이름 — Prometheus 에서는 {@code dodam_push_sending_enabled} 로 노출된다. */
  static final String SENDING_ENABLED_GAUGE = "dodam.push.sending.enabled";

  private final PushSender pushSender;
  private final FcmProperties properties;

  /**
   * 실제로 주입된 발송기와 설정을 비교해 상태를 판정한다.
   *
   * @param pushSender 컨텍스트에 선 발송기 구현 (FCM 또는 no-op)
   * @param properties FCM 발송 설정
   * @param meterRegistry 게이지 등록 대상
   */
  public PushHealthIndicator(
      PushSender pushSender, FcmProperties properties, MeterRegistry meterRegistry) {
    this.pushSender = pushSender;
    this.properties = properties;
    Gauge.builder(SENDING_ENABLED_GAUGE, pushSender, sender -> sender.isEnabled() ? 1.0D : 0.0D)
        .description("푸시를 실제로 발송할 수 있으면 1, 아니면 0")
        .tag("configured", Boolean.toString(properties.enabled()))
        .register(meterRegistry);
  }

  /** 설정은 켜졌는데 실제로는 발송할 수 없는 상태. */
  boolean isDegraded() {
    return properties.enabled() && !pushSender.isEnabled();
  }

  @Override
  public Health health() {
    Health.Builder builder =
        Health.up()
            .withDetail("configured", properties.enabled())
            .withDetail("sending", pushSender.isEnabled())
            .withDetail("degraded", isDegraded());
    if (isDegraded()) {
      builder.withDetail(
          "reason", FcmCredentials.inspect(properties.credentialsPath()).reason());
    }
    return builder.build();
  }
}
