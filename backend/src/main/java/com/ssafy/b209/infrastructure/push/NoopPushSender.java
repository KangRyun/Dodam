package com.ssafy.b209.infrastructure.push;

import com.ssafy.b209.notification.push.PushMessage;
import com.ssafy.b209.notification.push.PushSendOutcome;
import com.ssafy.b209.notification.push.PushSender;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Conditional;
import org.springframework.stereotype.Component;

/**
 * FCM 발송을 할 수 없는 환경에서 활성화되는 no-op {@link PushSender}다.
 *
 * <p>발송을 조용히 건너뛰며(계약 §0-6) 자격증명 없이도 부팅한다. 호출부는 {@link #isEnabled()}가 {@code false}이면 발송을 시도하지 않으므로
 * {@link #send(PushMessage)}는 실행되지 않는다.
 *
 * <p>이 Bean이 서는 경우는 둘이다 — 스위치가 꺼진 정상 상태와, <b>켜려 했으나 자격증명을 쓸 수 없는</b> 비정상 상태다. 뒤쪽은 반드시 눈에 띄어야 한다.
 * "설정은 켜져 있는데 실제로는 동작하지 않는 상태"가 조용히 유지되는 것이 이 시스템에서 반복된 실패 모드이기 때문이다(S15P11B209-681).
 */
@Component
@Conditional(FcmUnavailableCondition.class)
public class NoopPushSender implements PushSender {

  private static final Logger log = LoggerFactory.getLogger(NoopPushSender.class);

  private final FcmProperties properties;

  /**
   * 발송이 왜 불가능한지 알리기 위해 설정을 주입받는다.
   *
   * @param properties FCM 발송 설정
   */
  public NoopPushSender(FcmProperties properties) {
    this.properties = properties;
  }

  /**
   * 기동 시 발송 비활성 사유를 한 번 남긴다.
   *
   * <p>스위치가 꺼진 경우는 의도된 구성이므로 INFO, 켜려다 실패한 경우는 운영자가 즉시 알아야 하므로 ERROR다. 자격증명 <b>내용</b>은 남기지 않고 경로와
   * 사유만 남긴다.
   */
  @PostConstruct
  void logDisabledReason() {
    if (!properties.enabled()) {
      log.info("FCM 발송이 꺼져 있습니다 — 알림함 기록만 남기고 발송은 건너뜁니다.");
      return;
    }
    FcmCredentials.Availability availability = FcmCredentials.inspect(properties.credentialsPath());
    log.error(
        "FCM 발송이 켜져 있으나 자격증명을 쓸 수 없어 발송을 비활성화한 채 기동합니다. "
            + "푸시는 전송되지 않습니다. path={} reason={}",
        properties.credentialsPath(),
        availability.reason());
  }

  @Override
  public boolean isEnabled() {
    return false;
  }

  @Override
  public PushSendOutcome send(PushMessage message) {
    return PushSendOutcome.TEMPORARY_FAILURE;
  }
}
