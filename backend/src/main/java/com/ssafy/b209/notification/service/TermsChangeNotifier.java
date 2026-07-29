package com.ssafy.b209.notification.service;

import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 약관 새 버전이 게시·변경될 때 호출해 재동의 안내 알림을 만들고 발송하는 진입점(훅)이다.
 *
 * <p>이 메서드를 실제로 호출하는 약관 게시·관리 기능은 아직 리포에 없다(557 as-built §호출부). 향후 약관 관리 기능이 새 {@code ConsentTerm}을
 * 시행할 때 {@link #notifyTermsUpdated(String, String)}를 호출하도록 배선한다. 지금은 명시적 서비스 진입점으로만 제공하며, 임의의 관리
 * CRUD·인증 없는 공개 엔드포인트를 만들지 않는다.
 *
 * <p>알림함 원본 생성({@link TermsChangeNotificationService})을 먼저 커밋한 뒤 발송({@link
 * NotificationPushDispatcher})을 부수효과로 수행한다. 생성 실패는 발송을 건너뛰고, 발송 실패는 삼켜서 로그만 남긴다(계약 §0-6·§0-7). 알림함
 * 원본은 발송 성공 여부와 무관하게 남는다.
 */
@Component
public class TermsChangeNotifier {

  private static final Logger log = LoggerFactory.getLogger(TermsChangeNotifier.class);

  private final TermsChangeNotificationService notificationService;
  private final NotificationPushDispatcher dispatcher;

  /**
   * 알림 생성 서비스와 푸시 발송 조율기를 주입받는다.
   *
   * @param notificationService 약관 변경 알림함 원본 생성 서비스
   * @param dispatcher 알림 한 건을 활성 기기로 발송하는 조율기
   */
  public TermsChangeNotifier(
      TermsChangeNotificationService notificationService, NotificationPushDispatcher dispatcher) {
    this.notificationService = notificationService;
    this.dispatcher = dispatcher;
  }

  /**
   * 변경된 약관의 재동의 대상에게 약관 변경 알림을 생성하고 각 알림을 발송한다.
   *
   * @param termCode 변경된 약관을 식별하는 안정적인 코드
   * @param newVersion 게시된 새 약관 버전. 트리거 맥락 로깅에만 쓰며 알림 본문에는 담지 않는다(계약 §6)
   */
  public void notifyTermsUpdated(String termCode, String newVersion) {
    log.info("약관 변경 알림 트리거를 수신했습니다. termCode={}, version={}", termCode, newVersion);
    List<CreatedNotification> notifications;
    try {
      notifications = notificationService.createConsentUpdated(termCode);
    } catch (RuntimeException exception) {
      log.warn(
          "약관 변경 알림 생성에 실패해 발송을 건너뜁니다. termCode={}, reason={}",
          termCode,
          exception.getClass().getSimpleName());
      return;
    }
    for (CreatedNotification notification : notifications) {
      try {
        dispatcher.dispatch(notification);
      } catch (RuntimeException exception) {
        log.warn(
            "약관 변경 푸시 발송에 실패했습니다. notificationId={}, reason={}",
            notification.notificationId(),
            exception.getClass().getSimpleName());
      }
    }
  }
}
