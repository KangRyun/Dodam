package com.ssafy.b209.notification.domain;

import java.util.Set;

/**
 * 알림 유형 어휘다. {@code notifications.notification_type} CHECK 제약과 같은 값 집합을 한 곳에서 관리한다.
 *
 * <p>목록 조회(NOTI-03)와 전체 읽음 처리(NOTI-05)가 같은 유형 필터를 검증하므로 값을 서비스마다 복제하지 않고 여기서 참조한다.
 */
public final class NotificationTypes {

  private static final Set<String> ALLOWED =
      Set.of(
          "ANALYSIS_COMPLETED",
          "ANALYSIS_FAILED",
          "REPORT_COMPLETED",
          "NEW_EXPERT_POST",
          "COMMENT_CREATED",
          "CONSENT_UPDATED",
          "RETENTION_NOTICE",
          "ACTIVITY_REMINDER",
          "RISK_REVIEW_GUIDE");

  private NotificationTypes() {}

  /**
   * 주어진 유형이 DB 제약이 허용하는 값인지 확인한다.
   *
   * @param type 확인할 알림 유형
   * @return 허용 어휘에 속하면 {@code true}
   */
  public static boolean isAllowed(String type) {
    return ALLOWED.contains(type);
  }
}
