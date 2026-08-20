package com.ssafy.b209.notification.service;

import com.ssafy.b209.report.service.ReportGenerationFailedEvent;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 리포트가 최종 실패로 확정된 뒤 보호자에게 실패 알림을 만들고 푸시를 발송한다.
 *
 * <p>{@link AnalysisCompletedPushListener}와 같은 규칙을 따른다 — 알림 생성이 실패하면 발송을 건너뛰고, 발송 실패는 알림함 원본과 실패
 * 기록을 되돌리지 않도록 삼켜서 로그만 남긴다(계약 §0-6·§0-7). 실패 요약(WARN)에는 예외 유형만 싣고 상세는 DEBUG에 남긴다 — 예외 메시지에는 SQL·제약
 * 이름이 섞일 수 있어 운영 로그에 그대로 두지 않는다(§5.4).
 *
 * <h2>왜 {@code fallbackExecution = true} 인가</h2>
 *
 * 이 이벤트는 <b>서로 다른 두 자리</b>에서 온다.
 *
 * <ul>
 *   <li>{@code ObservationReportPersistenceService.markFailed} — 실패 기록 Transaction 안에서 발행하므로 커밋 후에
 *       실행돼야 한다.
 *   <li>{@code ReportGenerationRetryWorker} — 재시도 한도를 다 쓴 리포트를 {@code FAILED_FINAL}로 내린 <b>뒤</b>, 그
 *       Transaction 밖에서 발행한다.
 * </ul>
 *
 * <p>기본값({@code false})이면 뒤엣것은 실행할 Transaction이 없다는 이유로 <b>조용히 버려진다</b> — 재시도를 다 써서 포기한 실패야말로 보호자가
 * 반드시 알아야 하는 경우인데 그 알림만 사라진다. {@code true}면 Transaction이 없을 때 즉시 실행하며, 그 시점에는 상태 변경이 이미 커밋돼 있어
 * 안전하다.
 */
@Component
public class ReportFailedPushListener {

  private static final Logger log = LoggerFactory.getLogger(ReportFailedPushListener.class);

  private final ReportFailedNotificationService notificationService;
  private final NotificationPushDispatcher dispatcher;

  /**
   * 알림 생성 서비스와 푸시 발송 조율기를 주입받는다.
   *
   * @param notificationService 리포트 실패 알림함 원본 생성 서비스
   * @param dispatcher 알림 한 건을 활성 기기로 발송하는 조율기
   */
  public ReportFailedPushListener(
      ReportFailedNotificationService notificationService, NotificationPushDispatcher dispatcher) {
    this.notificationService = notificationService;
    this.dispatcher = dispatcher;
  }

  /**
   * 최종 실패 확정 후 보호자 알림을 생성하고 각 알림을 발송한다.
   *
   * @param event 최종 실패한 리포트 식별자를 담은 이벤트
   */
  @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
  public void onReportGenerationFailed(ReportGenerationFailedEvent event) {
    List<CreatedNotification> notifications;
    try {
      notifications = notificationService.createReportFailed(event.reportId());
    } catch (RuntimeException exception) {
      log.warn(
          "리포트 실패 알림 생성에 실패해 발송을 건너뜁니다. reportId={}, reason={}",
          event.reportId(),
          exception.getClass().getSimpleName());
      log.debug("리포트 실패 알림 생성 실패 상세입니다. reportId={}", event.reportId(), exception);
      return;
    }
    log.info("리포트 실패 알림을 발송합니다. reportId={}, count={}", event.reportId(), notifications.size());
    for (CreatedNotification notification : notifications) {
      try {
        dispatcher.dispatch(notification);
      } catch (RuntimeException exception) {
        log.warn(
            "리포트 실패 푸시 발송에 실패했습니다. notificationId={}, reason={}",
            notification.notificationId(),
            exception.getClass().getSimpleName());
        log.debug(
            "리포트 실패 푸시 발송 실패 상세입니다. notificationId={}", notification.notificationId(), exception);
      }
    }
  }
}
