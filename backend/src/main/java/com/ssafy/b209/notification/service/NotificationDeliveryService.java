package com.ssafy.b209.notification.service;

import com.ssafy.b209.notification.domain.NotificationDeviceToken;
import com.ssafy.b209.notification.repository.NotificationDeviceTokenRepository;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 발송 결과를 알림 전송 상태와 죽은 Token 비활성화에 반영한다.
 *
 * <p>발송은 완료 Transaction 밖의 부수효과이므로 이 갱신도 짧은 독립 Transaction으로 처리한다. 대상이 이미 사라졌으면 조용히 넘어간다.
 *
 * <p>독립 Transaction을 {@code REQUIRES_NEW}로 못박는다. 이 서비스는 분석 완료 알림처럼 리포트 완료 Transaction의 커밋 후 단계에서도
 * 호출되는데, 그 시점에는 이미 커밋된 Transaction 자원이 Thread에 남아 있어 {@code REQUIRED}는 새 Transaction을 시작하지 않고 그 자원에
 * 참여한다. 그러면 Dirty Checking 결과를 flush·commit할 주체가 없어 전송 상태가 {@code PENDING}에 머문다(S15P11B209-749).
 */
@Service
public class NotificationDeliveryService {

  private final NotificationRepository notificationRepository;
  private final NotificationDeviceTokenRepository deviceTokenRepository;
  private final Clock clock;

  /**
   * 알림·기기 Token 저장소와 시각 기준을 연결한다.
   *
   * @param notificationRepository 알림 저장소
   * @param deviceTokenRepository 기기 Token 저장소
   * @param clock 서버 기준 시계
   */
  public NotificationDeliveryService(
      NotificationRepository notificationRepository,
      NotificationDeviceTokenRepository deviceTokenRepository,
      Clock clock) {
    this.notificationRepository = notificationRepository;
    this.deviceTokenRepository = deviceTokenRepository;
    this.clock = clock;
  }

  /**
   * 발송 결과를 알림 전송 상태에 반영한다.
   *
   * @param notificationId 대상 알림 식별자
   * @param sent 한 기기 이상에 발송이 성공했으면 {@code true}
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void markDelivered(long notificationId, boolean sent) {
    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    notificationRepository
        .findById(notificationId)
        .ifPresent(
            notification -> {
              if (sent) {
                notification.markSent(now);
              } else {
                notification.markFailed(now);
              }
            });
  }

  /**
   * FCM이 만료·형식 오류로 판정한 기기 Token을 비활성화한다. 행은 남긴다(계약 §5.3).
   *
   * @param tokenId 비활성화할 기기 Token 식별자
   */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void deactivateDeviceToken(long tokenId) {
    deviceTokenRepository.findById(tokenId).ifPresent(NotificationDeviceToken::deactivate);
  }
}
