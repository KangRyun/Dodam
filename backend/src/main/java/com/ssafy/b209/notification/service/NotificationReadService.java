package com.ssafy.b209.notification.service;

import com.ssafy.b209.global.exception.BusinessException;
import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.dto.response.NotificationReadResponse;
import com.ssafy.b209.notification.exception.NotificationErrorCode;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * NOTI-04 단건 알림 읽음 처리 Use Case다.
 *
 * <p>멱등하다. 이미 읽은 알림을 다시 호출해도 최초 {@code readAt}을 유지하고 같은 응답을 준다. 다른 사용자의 알림은 접근 거부가 아니라 미존재로 응답해 알림
 * ID의 존재 여부를 숨긴다.
 */
@Service
public class NotificationReadService {

  private final NotificationRepository notificationRepository;
  private final Clock clock;

  /**
   * 알림 저장소와 시각 기준을 연결한다.
   *
   * @param notificationRepository 수신자 소유 확인과 상태 변경 저장소
   * @param clock 서버 기준 시계
   */
  public NotificationReadService(NotificationRepository notificationRepository, Clock clock) {
    this.notificationRepository = notificationRepository;
    this.clock = clock;
  }

  /**
   * 수신자 본인의 알림을 읽음 처리한다.
   *
   * @param recipientUserId 인증된 수신자 사용자 ID
   * @param notificationId 읽음 처리할 알림 ID
   * @return 알림 ID와 최초로 읽은 시각
   * @throws BusinessException 알림이 없거나 요청자의 알림이 아닌 경우
   */
  @Transactional
  public NotificationReadResponse markRead(Long recipientUserId, Long notificationId) {
    Notification notification =
        notificationRepository
            .findByIdAndRecipientUserId(notificationId, recipientUserId)
            .orElseThrow(() -> new BusinessException(NotificationErrorCode.NOTIFICATION_NOT_FOUND));
    if (notification.markRead(LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC))) {
      notificationRepository.saveAndFlush(notification);
    }
    return new NotificationReadResponse(notification.getId(), notification.getReadAt());
  }
}
