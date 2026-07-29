package com.ssafy.b209.notification.service;

import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.repository.NotificationRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 보관 만료가 임박한 데이터의 소유 보호자에게 남길 알림함 원본을 생성한다.
 *
 * <p>발송 성공 여부와 무관하게 알림함 기록이 먼저 남아야 하므로(계약 §0-4·§5.1) 이 저장은 발송과 분리된 독립 Transaction에서 수행한다. 발송은
 * {@link RetentionNoticeScheduler}가 이 Transaction이 커밋된 뒤 부수효과로 호출한다.
 *
 * <p>보관 만료 안내는 연결할 자원이 없으므로 관련 자원 ID를 모두 비운다(계약 §3의 {@code relatedResourceType} 없음과 일치). 본문은 어떤
 * 데이터인지·아동 정보를 담지 않는 중립 문구만 사용한다(§6).
 */
@Service
public class RetentionNoticeNotificationService {

  private static final String TYPE = "RETENTION_NOTICE";
  private static final String TITLE = "보관 기간이 곧 만료돼요";
  private static final String CONTENT = "보관 기간이 만료되기 전에 확인해 주세요";

  private final NotificationRepository notificationRepository;
  private final Clock clock;

  /**
   * 알림 저장소와 시각 기준을 연결한다.
   *
   * @param notificationRepository 알림 저장소
   * @param clock 서버 기준 시계
   */
  public RetentionNoticeNotificationService(
      NotificationRepository notificationRepository, Clock clock) {
    this.notificationRepository = notificationRepository;
    this.clock = clock;
  }

  /**
   * 보관 만료 임박 데이터의 소유 보호자마다 보관 만료 알림함 원본을 생성한다.
   *
   * @param ownerUserIds 보관 만료 임박 데이터의 소유 보호자 사용자 ID 목록
   * @return 저장된 알림의 발송용 요약 목록이며 대상이 없으면 빈 목록
   */
  @Transactional
  public List<CreatedNotification> createRetentionNotices(List<Long> ownerUserIds) {
    if (ownerUserIds.isEmpty()) {
      return List.of();
    }
    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    List<CreatedNotification> created = new ArrayList<>();
    for (Long ownerUserId : ownerUserIds) {
      Notification saved =
          notificationRepository.save(
              Notification.create(ownerUserId, TYPE, TITLE, CONTENT, null, null, null, now));
      created.add(
          new CreatedNotification(saved.getId(), ownerUserId, TYPE, TITLE, CONTENT, null, null));
    }
    return created;
  }
}
