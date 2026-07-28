package com.ssafy.b209.notification.service;

import com.ssafy.b209.report.service.AnalysisCompletedEvent;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 리포트 완료 Transaction이 커밋된 뒤 분석 완료 알림을 만들고 푸시를 발송한다.
 *
 * <p>커밋 후에 실행하므로 완료 처리 자체에는 영향을 주지 않는다. 알림 생성이 실패하면 발송을 건너뛰고, 발송 실패는 알림함 원본과 완료 처리를 되돌리지 않도록 삼켜서
 * 로그만 남긴다(계약 §0-6·§0-7). 알림함 원본은 발송 성공 여부와 무관하게 남는다.
 */
@Component
public class AnalysisCompletedPushListener {

  private static final Logger log = LoggerFactory.getLogger(AnalysisCompletedPushListener.class);

  private final AnalysisCompletedNotificationService notificationService;
  private final NotificationPushDispatcher dispatcher;

  /**
   * 알림 생성 서비스와 푸시 발송 조율기를 주입받는다.
   *
   * @param notificationService 분석 완료 알림함 원본 생성 서비스
   * @param dispatcher 알림 한 건을 활성 기기로 발송하는 조율기
   */
  public AnalysisCompletedPushListener(
      AnalysisCompletedNotificationService notificationService,
      NotificationPushDispatcher dispatcher) {
    this.notificationService = notificationService;
    this.dispatcher = dispatcher;
  }

  /**
   * 완료 커밋 후 보호자 알림을 생성하고 각 알림을 발송한다.
   *
   * @param event 완료된 리포트 식별자를 담은 이벤트
   */
  @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
  public void onAnalysisCompleted(AnalysisCompletedEvent event) {
    List<CreatedNotification> notifications;
    try {
      notifications = notificationService.createAnalysisCompleted(event.reportId());
    } catch (RuntimeException exception) {
      log.warn(
          "분석 완료 알림 생성에 실패해 발송을 건너뜁니다. reportId={}, reason={}",
          event.reportId(),
          exception.getClass().getSimpleName());
      return;
    }
    for (CreatedNotification notification : notifications) {
      try {
        dispatcher.dispatch(notification);
      } catch (RuntimeException exception) {
        log.warn(
            "분석 완료 푸시 발송에 실패했습니다. notificationId={}, reason={}",
            notification.notificationId(),
            exception.getClass().getSimpleName());
      }
    }
  }
}
