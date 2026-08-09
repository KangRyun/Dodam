package com.ssafy.b209.user.service;

import com.ssafy.b209.user.dto.response.NotificationSettingsResponse;
import com.ssafy.b209.user.repository.UserNotificationSettingsRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 사용자 응답에 포함할 알림 수신 설정을 조회한다.
 *
 * <p>사용자마다 {@code user_notification_settings} 행이 항상 존재한다고 보장할 수 없으므로, 행이 없으면 컬럼 DEFAULT와 동일한 기본값을
 * 반환해 응답 계약에서 {@code notificationSettings}가 누락되지 않게 한다.
 */
@Service
@Transactional(readOnly = true)
public class UserNotificationSettingsReader {

  private final UserNotificationSettingsRepository notificationSettingsRepository;

  /**
   * 알림 설정 조회기를 구성한다.
   *
   * @param notificationSettingsRepository 알림 설정 읽기 저장소
   */
  public UserNotificationSettingsReader(
      UserNotificationSettingsRepository notificationSettingsRepository) {
    this.notificationSettingsRepository = notificationSettingsRepository;
  }

  /**
   * 사용자의 알림 수신 설정을 반환한다.
   *
   * @param userId 조회할 사용자 식별자
   * @return 저장된 알림 설정이며, 저장 행이 없으면 기본값
   */
  public NotificationSettingsResponse read(Long userId) {
    return notificationSettingsRepository
        .findByUserId(userId)
        .map(
            projection ->
                new NotificationSettingsResponse(
                    projection.getAnalysisCompleted(),
                    projection.getCommunity(),
                    projection.getServiceNotice(),
                    projection.getMarketing()))
        .orElseGet(NotificationSettingsResponse::defaults);
  }
}
