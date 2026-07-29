package com.ssafy.b209.notification.service;

import com.ssafy.b209.notification.domain.Notification;
import com.ssafy.b209.notification.repository.NotificationRepository;
import com.ssafy.b209.notification.repository.TermsChangeRecipientRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 약관이 변경됐을 때 재동의가 필요한 사용자에게 남길 알림함 원본을 생성한다.
 *
 * <p>발송 성공 여부와 무관하게 알림함 기록이 먼저 남아야 하므로(계약 §0-4·§5.1) 이 저장은 발송과 분리된 독립 Transaction에서 수행한다. 발송은
 * {@link TermsChangeNotifier}가 이 Transaction이 커밋된 뒤 부수효과로 호출한다.
 *
 * <p>약관 변경은 연결할 자원이 없으므로 관련 자원 ID를 모두 비운다(계약 §3의 {@code relatedResourceType} 없음과 일치). 본문은 어떤
 * 약관인지·무엇이 바뀌었는지 담지 않는 중립 문구만 사용한다(§6).
 */
@Service
public class TermsChangeNotificationService {

  private static final String TYPE = "CONSENT_UPDATED";
  private static final String TITLE = "약관이 변경되었어요";
  private static final String CONTENT = "변경된 약관을 확인해 주세요";

  private final NotificationRepository notificationRepository;
  private final TermsChangeRecipientRepository recipientRepository;
  private final Clock clock;

  /**
   * 알림 저장소, 수신자 해석 저장소, 시각 기준을 연결한다.
   *
   * @param notificationRepository 알림 저장소
   * @param recipientRepository 활성 동의 사용자 해석 저장소
   * @param clock 서버 기준 시계
   */
  public TermsChangeNotificationService(
      NotificationRepository notificationRepository,
      TermsChangeRecipientRepository recipientRepository,
      Clock clock) {
    this.notificationRepository = notificationRepository;
    this.recipientRepository = recipientRepository;
    this.clock = clock;
  }

  /**
   * 변경된 약관에 활성 동의를 보유한 사용자마다 약관 변경 알림함 원본을 생성한다.
   *
   * @param termCode 변경된 약관을 식별하는 안정적인 코드
   * @return 저장된 알림의 발송용 요약 목록이며 수신 대상이 없으면 빈 목록
   */
  @Transactional
  public List<CreatedNotification> createConsentUpdated(String termCode) {
    List<Long> recipientUserIds = recipientRepository.findActiveConsentUserIdsByTermCode(termCode);
    if (recipientUserIds.isEmpty()) {
      return List.of();
    }
    LocalDateTime now = LocalDateTime.ofInstant(clock.instant(), ZoneOffset.UTC);
    List<CreatedNotification> created = new ArrayList<>();
    for (Long recipientUserId : recipientUserIds) {
      Notification saved =
          notificationRepository.save(
              Notification.create(recipientUserId, TYPE, TITLE, CONTENT, null, null, null, now));
      created.add(
          new CreatedNotification(
              saved.getId(), recipientUserId, TYPE, TITLE, CONTENT, null, null));
    }
    return created;
  }
}
