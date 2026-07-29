package com.ssafy.b209.notification.service;

import com.ssafy.b209.notification.repository.RetentionExpiryRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 보관 만료가 임박한 데이터의 소유 보호자에게 보관 만료 알림을 주기적으로 만들고 발송한다.
 *
 * <p>데이터 보관 정책(S15P11B209-564·565)이 확정되기 전이라 {@link RetentionNoticeProperties#isEnabled()}가 기본
 * {@code false}이며, 꺼져 있으면 이 작업은 조회·생성·발송 어느 것도 하지 않는다. 가짜 기준일로 알림을 오발송하지 않기 위한 게이트다. 보관 정책이 확정되면 실제
 * 만료 시각·재알림 억제를 그 도메인이 소유하고, 지금의 삭제 시각 기준·매 실행 재조회는 임시 구현이다(557 as-built §보관 만료 기준).
 *
 * <p>알림함 원본 생성({@link RetentionNoticeNotificationService})을 먼저 커밋한 뒤 발송({@link
 * NotificationPushDispatcher})을 부수효과로 수행한다. 개별 발송 실패는 삼켜서 다음 대상 발송을 막지 않는다(계약 §0-6·§0-7).
 */
@Component
public class RetentionNoticeScheduler {

  private static final Logger log = LoggerFactory.getLogger(RetentionNoticeScheduler.class);

  private final RetentionExpiryRepository expiryRepository;
  private final RetentionNoticeNotificationService notificationService;
  private final NotificationPushDispatcher dispatcher;
  private final RetentionNoticeProperties properties;
  private final Clock clock;

  /**
   * 만료 대상 조회, 알림 생성, 발송 조율, 실행 조건, 시각 기준을 연결한다.
   *
   * @param expiryRepository 보관 만료 임박 데이터 소유자 조회 저장소
   * @param notificationService 보관 만료 알림함 원본 생성 서비스
   * @param dispatcher 알림 한 건을 활성 기기로 발송하는 조율기
   * @param properties 실행 여부·기준일·배치 크기
   * @param clock 서버 기준 시계
   */
  public RetentionNoticeScheduler(
      RetentionExpiryRepository expiryRepository,
      RetentionNoticeNotificationService notificationService,
      NotificationPushDispatcher dispatcher,
      RetentionNoticeProperties properties,
      Clock clock) {
    this.expiryRepository = expiryRepository;
    this.notificationService = notificationService;
    this.dispatcher = dispatcher;
    this.properties = properties;
    this.clock = clock;
  }

  /**
   * 보관 만료가 임박한 데이터의 소유 보호자에게 보관 만료 알림을 만들고 발송한다.
   *
   * <p>실행이 꺼져 있으면 아무것도 하지 않는다. 만료 임박 기준일은 {@code 현재 - 보관 기간 + 안내 선행일}로 계산해, 그 이전에 삭제돼 만료가 안내 시점에
   * 들어온 데이터만 대상으로 한다.
   */
  @Scheduled(fixedDelayString = "${app.notification.retention.interval:1h}")
  public void notifyExpiringRetention() {
    if (!properties.isEnabled()) {
      return;
    }
    LocalDateTime cutoff =
        LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC)
            .minusDays(properties.getRetentionDays())
            .plusDays(properties.getNoticeDaysBefore());
    List<Long> ownerUserIds =
        expiryRepository.findExpiringDataOwnerUserIds(cutoff, properties.getBatchSize());
    if (ownerUserIds.isEmpty()) {
      return;
    }
    List<CreatedNotification> notifications;
    try {
      notifications = notificationService.createRetentionNotices(ownerUserIds);
    } catch (RuntimeException exception) {
      log.warn(
          "보관 만료 알림 생성에 실패해 발송을 건너뜁니다. count={}, reason={}",
          ownerUserIds.size(),
          exception.getClass().getSimpleName());
      return;
    }
    log.info("보관 만료 임박 알림을 발송합니다. count={}", notifications.size());
    for (CreatedNotification notification : notifications) {
      try {
        dispatcher.dispatch(notification);
      } catch (RuntimeException exception) {
        log.warn(
            "보관 만료 푸시 발송에 실패했습니다. notificationId={}, reason={}",
            notification.notificationId(),
            exception.getClass().getSimpleName());
      }
    }
  }
}
